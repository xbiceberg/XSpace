import Foundation
import AppKit

// MARK: - 7-Zip 界面：压缩参数 / 解压参数 / 压缩包浏览

enum SevenZipIcon {
    static func image(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "sevenzip"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }
    static var archive: NSImage? { image("RAR") }
    static var add: NSImage? { image("Add") }
    static var extract: NSImage? { image("Extract") }
    static var extractTo: NSImage? { image("ExtractTo") }
    static var view: NSImage? { image("View") }
}

// MARK: - 通用面板构建工具

private enum PanelUI {
    static func label(_ text: String, frame: NSRect, bold: Bool = false) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.frame = frame
        f.font = bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
        f.alignment = .right
        return f
    }

    static func field(_ value: String, frame: NSRect) -> NSTextField {
        let f = NSTextField(string: value)
        f.frame = frame
        f.font = .systemFont(ofSize: 13)
        f.bezelStyle = .roundedBezel
        return f
    }

    static func popup(_ items: [String], frame: NSRect) -> NSPopUpButton {
        let p = NSPopUpButton(frame: frame, pullsDown: false)
        p.addItems(withTitles: items)
        p.font = .systemFont(ofSize: 13)
        return p
    }

    static func button(_ title: String, frame: NSRect, target: Any?, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.frame = frame
        b.bezelStyle = .rounded
        b.font = .systemFont(ofSize: 13)
        return b
    }

    static func checkbox(_ title: String, frame: NSRect) -> NSButton {
        let b = NSButton(frame: frame)
        b.setButtonType(.switch)
        b.title = title
        b.font = .systemFont(ofSize: 13)
        return b
    }
}

// MARK: - 压缩参数面板

final class SevenZipCompressPanel: NSObject {
    var onConfirm: ((URL, SevenZip.CompressOptions) -> Void)?

    private var window: NSWindow!
    private var nameField: NSTextField!
    private var formatPopup: NSPopUpButton!
    private var levelPopup: NSPopUpButton!
    private var dictPopup: NSPopUpButton!
    private var volumeField: NSTextField!
    private var passwordField: NSTextField!
    private var deleteCheck: NSButton!
    private var directory: URL
    private var defaultBaseName: String

    init(directory: URL, defaultBaseName: String) {
        self.directory = directory
        self.defaultBaseName = defaultBaseName
    }

    func run() {
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
        NSApp.runModal(for: window)
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "压缩文件名和参数"
        window.isReleasedWhenClosed = false

        let root = NSView(frame: window.contentView!.bounds)
        window.contentView = root

        func addLabel(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, bold: Bool = false) {
            let l = PanelUI.label(text, frame: NSRect(x: x, y: y, width: w, height: 22), bold: bold)
            root.addSubview(l)
        }

        addLabel("压缩文件名：", 24, 350, 90)
        nameField = PanelUI.field("\(defaultBaseName).7z", frame: NSRect(x: 120, y: 348, width: 300, height: 24))
        root.addSubview(nameField)
        let hint = NSTextField(labelWithString: "保存在：\(directory.path)")
        hint.frame = NSRect(x: 24, y: 326, width: 470, height: 18)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingMiddle
        root.addSubview(hint)

        addLabel("压缩格式：", 24, 286, 90)
        formatPopup = PanelUI.popup(["7z（推荐）", "ZIP", "TAR"], frame: NSRect(x: 120, y: 284, width: 180, height: 24))
        let formatIndex = ["7z", "zip", "tar"].firstIndex(of: AppSettings.sevenZipFormat) ?? 0
        formatPopup.selectItem(at: formatIndex)
        let defaultExt = ["7z", "zip", "tar"][formatIndex]
        nameField.stringValue = "\(defaultBaseName).\(defaultExt)"
        root.addSubview(formatPopup)

        addLabel("压缩级别：", 24, 250, 90)
        levelPopup = PanelUI.popup(["0 - 存储", "1 - 最快", "3 - 快速", "5 - 标准", "7 - 最大", "9 - 极限"],
                                   frame: NSRect(x: 120, y: 248, width: 180, height: 24))
        let levelValues = [0, 1, 3, 5, 7, 9]
        levelPopup.selectItem(at: levelValues.firstIndex(of: AppSettings.sevenZipLevel) ?? 3)
        root.addSubview(levelPopup)

        addLabel("字典大小：", 24, 214, 90)
        dictPopup = PanelUI.popup(["8 MB", "16 MB", "32 MB", "64 MB", "128 MB", "256 MB"],
                                  frame: NSRect(x: 120, y: 212, width: 180, height: 24))
        dictPopup.selectItem(at: 2)
        root.addSubview(dictPopup)

        addLabel("分卷大小：", 24, 178, 90)
        volumeField = PanelUI.field("", frame: NSRect(x: 120, y: 176, width: 180, height: 24))
        volumeField.placeholderString = "不分卷（如 100 表示 100MB）"
        root.addSubview(volumeField)

        addLabel("密码：", 24, 142, 90)
        passwordField = PanelUI.field("", frame: NSRect(x: 120, y: 140, width: 180, height: 24))
        passwordField.placeholderString = "留空则不加密"
        root.addSubview(passwordField)

        deleteCheck = PanelUI.checkbox("压缩后删除原文件", frame: NSRect(x: 120, y: 106, width: 220, height: 22))
        root.addSubview(deleteCheck)

        let cancel = PanelUI.button("取消", frame: NSRect(x: 300, y: 36, width: 90, height: 30),
                                    target: self, action: #selector(cancel(_:)))
        let ok = PanelUI.button("确定", frame: NSRect(x: 400, y: 36, width: 90, height: 30),
                                target: self, action: #selector(confirm(_:)))
        ok.keyEquivalent = "\r"
        root.addSubview(cancel)
        root.addSubview(ok)

        let note = NSTextField(labelWithString: "开源版 7-Zip 支持 7z / ZIP / TAR；RAR 为专有格式，仅支持解压。")
        note.frame = NSRect(x: 24, y: 10, width: 470, height: 18)
        note.font = .systemFont(ofSize: 10)
        note.textColor = .tertiaryLabelColor
        root.addSubview(note)

        window.initialFirstResponder = nameField
    }

    @objc private func confirm(_ sender: Any) {
        let rawName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else {
            Dialog.alert(title: "请输入压缩文件名", message: "压缩文件名不能为空。", window: window)
            return
        }
        let formats = ["7z", "zip", "tar"]
        let format = formats[min(max(formatPopup.indexOfSelectedItem, 0), formats.count - 1)]
        let levels = [0, 1, 3, 5, 7, 9]
        let dicts = [8, 16, 32, 64, 128, 256]
        var options = SevenZip.CompressOptions()
        options.format = format
        options.level = levels[min(max(levelPopup.indexOfSelectedItem, 0), levels.count - 1)]
        options.dictionaryMB = dicts[min(max(dictPopup.indexOfSelectedItem, 0), dicts.count - 1)]
        options.volumeMB = Int(volumeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        options.password = passwordField.stringValue
        options.deleteSource = deleteCheck.state == .on

        var name = rawName
        let wantedExt = options.fileExtension
        if (name as NSString).pathExtension.lowercased() != wantedExt {
            name = "\(name).\(wantedExt)"
        }
        let archive = directory.appendingPathComponent(name)
        onConfirm?(archive, options)
        NSApp.stopModal()
        window.orderOut(nil)
    }

    @objc private func cancel(_ sender: Any) {
        NSApp.stopModal()
        window.orderOut(nil)
    }
}

// MARK: - 解压参数面板

final class SevenZipExtractPanel: NSObject {
    var onConfirm: ((URL, String) -> Void)?

    private var window: NSWindow!
    private var pathField: NSTextField!
    private var passwordField: NSTextField!
    private var modePopup: NSPopUpButton!
    private var initialPath: String

    init(initialPath: String) { self.initialPath = initialPath }

    func run() {
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
        NSApp.runModal(for: window)
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 230),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "解压文件"
        window.isReleasedWhenClosed = false
        let root = NSView(frame: window.contentView!.bounds)
        window.contentView = root

        let l1 = PanelUI.label("目标路径：", frame: NSRect(x: 24, y: 172, width: 90, height: 22))
        root.addSubview(l1)
        pathField = PanelUI.field(initialPath, frame: NSRect(x: 120, y: 170, width: 370, height: 24))
        root.addSubview(pathField)

        let browse = PanelUI.button("选择…", frame: NSRect(x: 120, y: 136, width: 80, height: 26),
                                    target: self, action: #selector(chooseDirectory(_:)))
        root.addSubview(browse)

        let l2 = PanelUI.label("密码：", frame: NSRect(x: 24, y: 104, width: 90, height: 22))
        root.addSubview(l2)
        passwordField = PanelUI.field("", frame: NSRect(x: 120, y: 102, width: 250, height: 24))
        passwordField.placeholderString = "加密压缩包时填写"
        root.addSubview(passwordField)

        let l3 = PanelUI.label("覆盖模式：", frame: NSRect(x: 24, y: 70, width: 90, height: 22))
        root.addSubview(l3)
        modePopup = PanelUI.popup(["替换已有文件", "跳过已有文件"], frame: NSRect(x: 120, y: 68, width: 200, height: 24))
        root.addSubview(modePopup)

        let cancel = PanelUI.button("取消", frame: NSRect(x: 300, y: 20, width: 90, height: 30),
                                    target: self, action: #selector(cancel(_:)))
        let ok = PanelUI.button("确定", frame: NSRect(x: 400, y: 20, width: 90, height: 30),
                                target: self, action: #selector(confirm(_:)))
        ok.keyEquivalent = "\r"
        root.addSubview(cancel)
        root.addSubview(ok)
        window.initialFirstResponder = pathField
    }

    @objc private func chooseDirectory(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.pathField.stringValue = url.path
        }
    }

    @objc private func confirm(_ sender: Any) {
        let path = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            Dialog.alert(title: "请输入目标路径", message: "目标路径不能为空。", window: window)
            return
        }
        onConfirm?(URL(fileURLWithPath: path), passwordField.stringValue)
        NSApp.stopModal()
        window.orderOut(nil)
    }

    @objc private func cancel(_ sender: Any) {
        NSApp.stopModal()
        window.orderOut(nil)
    }
}

// MARK: - 压缩包浏览窗口

final class ArchiveBrowserController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    /// 强引用持有所有打开的浏览窗口，避免控制器被释放导致表格代理失效
    private static var openBrowsers: [ArchiveBrowserController] = []

    private let archive: URL
    private let tempRoot: URL
    private var rootURL: URL
    private var currentURL: URL
    private var items: [ArchiveEntryItem] = []
    private var tableView: NSTableView!
    private var pathLabel: NSTextField!

    init(archive: URL) {
        self.archive = archive
        self.tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("XSpace-7z-view-\(UUID().uuidString)", isDirectory: true)
        self.rootURL = tempRoot
        self.currentURL = tempRoot
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "7-Zip — \(archive.lastPathComponent)"
        super.init(window: window)
        window.delegate = self
        buildUI()
        Self.openBrowsers.append(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func buildUI() {
        guard let window else { return }
        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        // 顶部工具栏
        let back = NSButton(title: "← 上级", target: self, action: #selector(goUp(_:)))
        back.frame = NSRect(x: 12, y: 522, width: 80, height: 28)
        back.bezelStyle = .rounded
        root.addSubview(back)

        pathLabel = NSTextField(labelWithString: "")
        pathLabel.frame = NSRect(x: 100, y: 525, width: 360, height: 22)
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.textColor = .secondaryLabelColor
        root.addSubview(pathLabel)

        let extractSelected = NSButton(title: "解压选中项到…", target: self, action: #selector(extractSelectedTo(_:)))
        extractSelected.frame = NSRect(x: 470, y: 522, width: 130, height: 28)
        extractSelected.bezelStyle = .rounded
        root.addSubview(extractSelected)

        let reveal = NSButton(title: "在访达中显示", target: self, action: #selector(revealInFinder(_:)))
        reveal.frame = NSRect(x: 668, y: 522, width: 136, height: 28)
        reveal.bezelStyle = .rounded
        root.addSubview(reveal)

        // 表格
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 820, height: 510))
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        scroll.borderType = .noBorder
        tableView = NSTableView(frame: scroll.bounds)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24
        tableView.headerView = NSTableHeaderView()
        // 支持 Shift/Command 点选与空白处鼠标框选；拖动时整批条目一起写入剪贴板
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .regular
        tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.doubleAction = #selector(doubleClick(_:))
        tableView.target = self
        for (identifier, title, width) in [("name", "名称", CGFloat(400)), ("size", "大小", CGFloat(110)), ("type", "类型", CGFloat(120)), ("date", "修改日期", CGFloat(170))] as [(String, String, CGFloat)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            col.title = title
            col.width = width
            tableView.addTableColumn(col)
        }
        scroll.documentView = tableView
        root.addSubview(scroll)

        let hint = NSTextField(labelWithString: "提示：Shift/Command 点选或在空白处框选多个文件，拖放到 XSpace 窗口即可解压；双击文件先解压再打开。")
        hint.frame = NSRect(x: 12, y: 512, width: 700, height: 16)
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        root.addSubview(hint)
    }

    /// 解压并展示（异步解压，避免阻塞 UI）
    func open(completion: ((Bool, String) -> Void)? = nil) {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = SevenZip.extract(self.archive, to: self.tempRoot)
            DispatchQueue.main.async {
                if !result.ok {
                    completion?(false, result.stderr.isEmpty ? "解压失败" : result.stderr)
                    return
                }
                self.navigate(to: self.tempRoot)
                completion?(true, "")
            }
        }
    }

    private func navigate(to url: URL) {
        currentURL = url
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        items = contents.map { ArchiveEntryItem(url: $0) }.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
        let relative = url.path.replacingOccurrences(of: tempRoot.path, with: "")
        pathLabel.stringValue = relative.isEmpty ? "压缩包根目录" : "压缩包根目录\(relative)"
        tableView.reloadData()
    }

    @objc private func goUp(_ sender: Any) {
        guard currentURL.path != tempRoot.path else { return }
        navigate(to: currentURL.deletingLastPathComponent())
    }

    @objc private func revealInFinder(_ sender: Any) {
        NSWorkspace.shared.activateFileViewerSelecting([currentURL])
    }

    /// 可靠兜底：把选中项按压缩包内相对路径直接解压到用户选择的目录，不依赖拖放手势。
    @objc private func extractSelectedTo(_ sender: Any) {
        let rows = tableView.selectedRowIndexes
        guard !rows.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "请先选择文件或文件夹"
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        var paths: [String] = []
        for row in rows {
            guard row < items.count else { continue }
            let relative = items[row].url.path.replacingOccurrences(of: tempRoot.path + "/", with: "")
            if !relative.isEmpty { paths.append(relative) }
        }
        guard !paths.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "解压到这里"
        panel.message = "将选中的 \(paths.count) 项解压到："
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let result = SevenZip.extract(self?.archive ?? URL(fileURLWithPath: ""), to: destination, paths: paths)
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    if result.ok {
                        alert.messageText = "解压完成"
                        alert.informativeText = "已解压 \(paths.count) 项到 \(destination.path)"
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "在访达中显示")
                        alert.addButton(withTitle: "好")
                        if alert.runModal() == .alertFirstButtonReturn {
                            NSWorkspace.shared.open(destination)
                        }
                    } else {
                        alert.messageText = "解压失败"
                        alert.informativeText = result.stderr.isEmpty ? "未知错误" : result.stderr
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        }
    }

    @objc private func doubleClick(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        if item.isDirectory {
            navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    // MARK: 数据源

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count, let column = tableColumn else { return nil }
        let item = items[row]
        let id = column.identifier
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: column.width, height: 24))
        switch id.rawValue {
        case "name":
            // 子视图不参与鼠标命中，避免 NSImageView/NSTextField 抢走框选与拖拽手势
            let iv = ArchiveCellImageView(frame: NSRect(x: 2, y: 3, width: 18, height: 18))
            iv.image = IconCache.icon(for: item.url, isDirectory: item.isDirectory)
            iv.imageScaling = .scaleProportionallyUpOrDown
            cell.addSubview(iv)
            let tf = ArchiveCellTextField(labelWithString: item.displayName)
            tf.frame = NSRect(x: 24, y: 3, width: column.width - 28, height: 18)
            tf.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(tf)
        case "size":
            let tf = ArchiveCellTextField(labelWithString: item.isDirectory ? "--" : FileSizeFormatter.string(item.size))
            tf.frame = NSRect(x: 4, y: 3, width: column.width - 8, height: 18)
            cell.addSubview(tf)
        case "type":
            let tf = ArchiveCellTextField(labelWithString: item.isDirectory ? "文件夹" : (item.url.pathExtension.uppercased().isEmpty ? "文件" : item.url.pathExtension.uppercased()))
            tf.frame = NSRect(x: 4, y: 3, width: column.width - 8, height: 18)
            cell.addSubview(tf)
        default:
            let tf = ArchiveCellTextField(labelWithString: item.modified.map { DateFormatterStore.medium.string(from: $0) } ?? "--")
            tf.frame = NSRect(x: 4, y: 3, width: column.width - 8, height: 18)
            cell.addSubview(tf)
        }
        return cell
    }

    /// 拖放源：NSTableView 会为所有选中行调用这里，因此框选/多选的一批文件会一起进入剪贴板。
    /// 附加私有标记后，XSpace 主窗口知道这是从压缩包拖出的，强制按“复制”处理。
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < items.count else { return nil }
        return FinderDragItem(items[row].url,
                              marker: (SevenZip.archiveDragMarker, "1"))
    }

    func windowWillClose(_ notification: Notification) {
        Self.openBrowsers.removeAll { $0 === self }
    }
}

// MARK: - 不拦截鼠标事件的表格单元格子视图
// NSTableView 的框选与拖拽依赖鼠标事件能到达表格本身；普通 NSImageView/NSTextField
// 会参与命中测试并吞掉 mouseDown/mouseDragged，导致无法框选或多选拖出。

private final class ArchiveCellImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class ArchiveCellTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isSelectable = false
        isEditable = false
        refusesFirstResponder = true
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    convenience init(labelWithString stringValue: String) {
        self.init(frame: .zero)
        self.stringValue = stringValue
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - 轻量文件条目

private struct ArchiveEntryItem {
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let modified: Date?
    let displayName: String

    init(url: URL) {
        self.url = url
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        self.isDirectory = values?.isDirectory ?? false
        self.size = Int64(values?.fileSize ?? 0)
        self.modified = values?.contentModificationDate
        self.displayName = FileManager.default.displayName(atPath: url.path)
    }
}
