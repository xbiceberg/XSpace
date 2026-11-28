import AppKit
import UniformTypeIdentifiers

/// 双击光标主题后打开：逐个光标状态重新选择 .ani / .cur，并写回 .cape。
final class CursorRemapWindowController: NSWindowController, NSTableViewDataSource,
                                         NSTableViewDelegate, NSWindowDelegate {
    private let theme: MousecapeTheme
    private var slots: [WindowsCursorConverter.CursorSlot]
    private var replacements: [String: URL] = [:]
    private let tableView = NSTableView(frame: .zero)
    private var onSaved: (() -> Void)?
    private var onClosed: (() -> Void)?
    private let previewCache = NSCache<NSString, NSImage>()

    init(theme: MousecapeTheme, onSaved: (() -> Void)? = nil, onClosed: (() -> Void)? = nil) {
        self.theme = theme
        self.slots = WindowsCursorConverter.cursorSlots(in: theme.url)
        self.onSaved = onSaved
        self.onClosed = onClosed

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "编辑光标状态 · \(theme.name)"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "双击某一行选择新的 Windows 光标文件（.ani / .cur），保存后写回主题。")
        title.frame = NSRect(x: 20, y: 466, width: 580, height: 18)
        title.font = NSFont.systemFont(ofSize: 11)
        title.textColor = .secondaryLabelColor
        content.addSubview(title)

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 66, width: 580, height: 388))
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        content.addSubview(scroll)

        tableView.frame = NSRect(x: 0, y: 0, width: 580, height: 388)
        tableView.rowHeight = 30
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(chooseCursorFile)
        tableView.style = .inset
        for (index, title) in ["光标状态", "当前图标", "帧数"].enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col\(index)"))
            column.title = title
            column.width = [210, 310, 60][index]
            tableView.addTableColumn(column)
        }

        let choose = NSButton(title: "选择 ANI…", target: self, action: #selector(chooseCursorFile))
        choose.frame = NSRect(x: 20, y: 22, width: 120, height: 28)
        choose.bezelStyle = .rounded
        content.addSubview(choose)

        let restore = NSButton(title: "恢复原文件", target: self, action: #selector(restoreOriginal))
        restore.frame = NSRect(x: 148, y: 22, width: 110, height: 28)
        restore.bezelStyle = .rounded
        content.addSubview(restore)

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 404, y: 22, width: 88, height: 28)
        cancel.bezelStyle = .rounded
        content.addSubview(cancel)

        let save = NSButton(title: "保存", target: self, action: #selector(save))
        save.frame = NSRect(x: 500, y: 22, width: 100, height: 28)
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        content.addSubview(save)
    }

    func windowWillClose(_ notification: Notification) {
        onClosed?()
        onClosed = nil
    }

    // MARK: - 表格

    func numberOfRows(in tableView: NSTableView) -> Int { slots.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier.rawValue, slots.indices.contains(row) else { return nil }
        let slot = slots[row]
        let cell = NSTableCellView()

        if identifier == "col1" {
            // 显示 ANI / CUR 第一帧，文件名放在提示里，避免列表被长文件名占满
            let url = replacements[slot.identifier]
                ?? slot.sourcePath.map { URL(fileURLWithPath: $0) }
            let imageView = NSImageView(frame: NSRect(x: 4, y: 3, width: 24, height: 24))
            imageView.image = url.flatMap { previewImage(for: $0) }
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.imageFrameStyle = .none
            let filename = url?.lastPathComponent ?? "未记录源文件"
            imageView.toolTip = replacements[slot.identifier] == nil
                ? filename
                : "已替换为：\(filename)"
            cell.addSubview(imageView)
            cell.imageView = imageView
            return cell
        }

        let field: NSTextField
        if identifier == "col0" {
            var name = WindowsCursorConverter.cursorDisplayName(for: slot.identifier)
            if !slot.role.isEmpty, slot.role != name {
                name = "\(name)（\(slot.role)）"
            }
            field = NSTextField(labelWithString: name)
            field.frame = NSRect(x: 4, y: 7, width: 200, height: 17)
            field.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        } else {
            field = NSTextField(labelWithString: "\(slot.frameCount)")
            field.frame = NSRect(x: 4, y: 7, width: 50, height: 17)
            field.font = NSFont.systemFont(ofSize: 11)
            field.textColor = .secondaryLabelColor
        }
        field.lineBreakMode = .byTruncatingMiddle
        cell.addSubview(field)
        cell.textField = field
        return cell
    }

    private func previewImage(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = previewCache.object(forKey: key) { return cached }
        guard let image = WindowsCursorConverter.previewImage(for: url) else { return nil }
        previewCache.setObject(image, forKey: key)
        return image
    }

    // MARK: - 操作

    @objc private func chooseCursorFile() {
        guard tableView.selectedRow >= 0, slots.indices.contains(tableView.selectedRow) else {
            Dialog.alert(title: "未选择光标状态", message: "请先在列表中选中一个光标状态。")
            return
        }
        let panel = NSOpenPanel()
        panel.title = "选择新的光标文件"
        panel.message = "为“\(WindowsCursorConverter.cursorDisplayName(for: slots[tableView.selectedRow].identifier))”选择 .ani 或 .cur。"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "ani"), UTType(filenameExtension: "cur")
        ].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        let row = tableView.selectedRow
        replacements[slots[row].identifier] = url
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<3))
    }

    @objc private func restoreOriginal() {
        guard tableView.selectedRow >= 0, slots.indices.contains(tableView.selectedRow) else { return }
        let row = tableView.selectedRow
        replacements.removeValue(forKey: slots[row].identifier)
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<3))
    }

    @objc private func cancel() {
        close()
    }

    @objc private func save() {
        guard !replacements.isEmpty else { close(); return }
        do {
            let wasApplied = MousecapeBridge.appliedCapeIdentifier() == theme.identifier
            try WindowsCursorConverter.rewrite(theme: theme.url, replacements: replacements)
            if wasApplied {
                DispatchQueue.global(qos: .utility).async {
                    _ = MousecapeBridge.applyCape(atPath: self.theme.url.path)
                }
            }
            onSaved?()
            onSaved = nil
            close()
        } catch {
            Dialog.alert(title: "保存失败", message: error.localizedDescription)
        }
    }
}
