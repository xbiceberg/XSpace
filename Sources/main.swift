import Foundation
import AppKit
import UniformTypeIdentifiers
import Carbon.HIToolbox

/// 偏好设置里用于录制快捷键的控件：点击后按下组合键即可保存
final class ShortcutRecorder: NSView {
    enum Kind { case screenshot, undo }

    private let label = NSTextField(labelWithString: "")
    private var readyToRecord = false
    var kind: Kind = .screenshot { didSet { updateDisplay() } }

    /// 当前控件对应的快捷键：截图或撤销
    private var shortcut: KeyShortcut {
        get { kind == .screenshot ? AppSettings.screenshotShortcut : AppSettings.undoShortcut }
        set {
            if kind == .screenshot { AppSettings.screenshotShortcut = newValue }
            else { AppSettings.undoShortcut = newValue }
        }
    }

    override var acceptsFirstResponder: Bool { readyToRecord }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.frame = NSRect(x: 10, y: 4, width: frameRect.width - 20, height: 18)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center
        label.textColor = .labelColor
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)
        updateDisplay()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        readyToRecord = true
        window?.makeFirstResponder(self)
        updateDisplay()
    }

    override func becomeFirstResponder() -> Bool {
        readyToRecord = true
        let ok = super.becomeFirstResponder()
        updateDisplay()
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        readyToRecord = false
        updateDisplay()
        return ok
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc 取消录制
            window?.makeFirstResponder(nil)
            return
        }
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        guard !flags.isEmpty else { // 至少需要一个修饰键，避免影响正常输入
            NSSound.beep()
            return
        }
        let character = (event.charactersIgnoringModifiers?.uppercased().first).map(String.init)
            ?? Self.keyName(for: event.keyCode)
        let newShortcut = KeyShortcut(keyCode: event.keyCode, modifiers: flags.rawValue, keyTitle: character)
        let other = kind == .screenshot ? AppSettings.undoShortcut : AppSettings.screenshotShortcut
        if newShortcut.conflicts(with: other) {
            NSSound.beep()
            let owner = kind == .screenshot ? "撤销" : "截图"
            Dialog.alert(title: "快捷键冲突", message: "该组合键已分配给「\(owner)」，请换一个。", window: window)
            return
        }
        shortcut = newShortcut
        window?.makeFirstResponder(nil)
        updateDisplay()
    }

    func refresh() { updateDisplay() }

    private func updateDisplay() {
        let active = window?.firstResponder === self
        label.stringValue = active ? "按下快捷键…" : shortcut.displayString
        layer?.borderColor = active
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
    }

    private static func keyName(for code: UInt16) -> String {
        let names: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑", 144: "F2"
        ]
        return names[code] ?? "键码\(code)"
    }
}

/// 偏好设置里录制「滚轮缩放修饰键」的控件：点击后按下 ⌃ / ⌥ / ⇧ / ⌘ 即设置为该键
final class ModifierRecorder: NSView {
    private let label = NSTextField(labelWithString: "")
    private var readyToRecord = false

    override var acceptsFirstResponder: Bool { readyToRecord }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.frame = NSRect(x: 10, y: 4, width: frameRect.width - 20, height: 18)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center
        label.textColor = .labelColor
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)
        updateDisplay()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        readyToRecord = true
        window?.makeFirstResponder(self)
        updateDisplay()
    }

    override func becomeFirstResponder() -> Bool {
        readyToRecord = true
        let ok = super.becomeFirstResponder()
        updateDisplay()
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        readyToRecord = false
        updateDisplay()
        return ok
    }

    /// 录制中按下修饰键立即生效（不松手也能识别）
    override func flagsChanged(with event: NSEvent) {
        guard readyToRecord else { return super.flagsChanged(with: event) }
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])
        guard let modifier = Self.modifier(for: flags) else { return }
        commit(modifier)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc 取消
            window?.makeFirstResponder(nil)
            return
        }
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])
        guard let modifier = Self.modifier(for: flags) else {
            NSSound.beep()
            return
        }
        commit(modifier)
    }

    private func commit(_ modifier: IconResizeModifier) {
        AppSettings.iconResizeModifier = modifier
        window?.makeFirstResponder(nil)
        updateDisplay()
    }

    func refresh() { updateDisplay() }

    private func updateDisplay() {
        let active = window?.firstResponder === self
        label.stringValue = active ? "按下修饰键…" : AppSettings.iconResizeModifier.title
        layer?.borderColor = active
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
    }

    private static func modifier(for flags: NSEvent.ModifierFlags) -> IconResizeModifier? {
        if flags.contains(.control) { return .control }
        if flags.contains(.option) { return .option }
        if flags.contains(.shift) { return .shift }
        if flags.contains(.command) { return .command }
        if flags.contains(.function) { return .function }
        return nil
    }
}

/// 偏好设置中的“右键菜单”页面：左侧为已启用项（可拖拽排序），右侧为可用功能
final class ContextMenuSettingsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let leftTableView = NSTableView()
    private let rightTableView = NSTableView()
    private var enabled: [ContextMenuItemID]
    private var selectedLeft = 0
    private var selectedRight = 0

    /// 右侧始终显示全部可自定义功能，便于直观看到有哪些可用项
    private var allItems: [ContextMenuItemID] { ContextMenuItemID.allCases }

    override init(frame frameRect: NSRect) {
        enabled = AppSettings.contextMenuItems
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        addSubview(SettingCardView(frame: NSRect(x: 16, y: 60, width: 528, height: 436)))
        let hint = NSTextField(labelWithString: "将右侧功能添加到左侧即可出现在右键菜单中；拖动左侧列表可调整顺序，移除后右键菜单中不再显示。")
        hint.frame = NSRect(x: 32, y: 478, width: 500, height: 32)
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        addSubview(hint)

        addSubview(makeSectionLabel("已启用的菜单项", x: 32))
        addSubview(makeSectionLabel("可用功能", x: 310))

        let leftScroll = makeScrollTableView(tableView: leftTableView, x: 32, tag: 1)
        let rightScroll = makeScrollTableView(tableView: rightTableView, x: 310, tag: 2)
        addSubview(leftScroll)
        addSubview(rightScroll)

        let add = makeButton("添加", frame: NSRect(x: 256, y: 386, width: 54, height: 26), action: #selector(addItem))
        let remove = makeButton("移除", frame: NSRect(x: 256, y: 346, width: 54, height: 26), action: #selector(removeItem))
        let up = makeButton("上移", frame: NSRect(x: 256, y: 296, width: 54, height: 26), action: #selector(moveItemUp))
        let down = makeButton("下移", frame: NSRect(x: 256, y: 256, width: 54, height: 26), action: #selector(moveItemDown))
        let reset = makeButton("恢复默认", frame: NSRect(x: 32, y: 94, width: 100, height: 28), action: #selector(resetItems))
        [add, remove, up, down, reset].forEach { addSubview($0) }

        leftTableView.registerForDraggedTypes([.string])
        rightTableView.doubleAction = #selector(tableDoubleClicked(_:))
        rightTableView.target = self
        reload()
    }

    private func makeSectionLabel(_ title: String, x: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: x, y: 450, width: 218, height: 20)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        return label
    }

    private func makeScrollTableView(tableView: NSTableView, x: CGFloat, tag: Int) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: x, y: 130, width: 218, height: 310))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .lineBorder
        scroll.drawsBackground = false

        tableView.frame = scroll.contentView.bounds
        tableView.autoresizingMask = [.width, .height]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tag = tag
        tableView.rowHeight = 24
        tableView.headerView = nil
        tableView.selectionHighlightStyle = .regular
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MenuItem"))
        column.width = scroll.contentSize.width
        tableView.addTableColumn(column)
        scroll.documentView = tableView
        return scroll
    }

    private func makeButton(_ title: String, frame: NSRect, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = frame
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 11)
        return button
    }

    private func reload() {
        leftTableView.reloadData()
        rightTableView.reloadData()
        if enabled.indices.contains(selectedLeft) {
            leftTableView.selectRowIndexes(IndexSet(integer: selectedLeft), byExtendingSelection: false)
        }
        if allItems.indices.contains(selectedRight) {
            rightTableView.selectRowIndexes(IndexSet(integer: selectedRight), byExtendingSelection: false)
        }
    }

    private func save() {
        AppSettings.contextMenuItems = enabled
        reload()
    }

    // MARK: - 表格数据

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === leftTableView ? enabled.count : allItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("MenuItemCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let newCell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            newCell.identifier = identifier
            let text = NSTextField(labelWithString: "")
            text.frame = NSRect(x: 6, y: 3, width: 190, height: 18)
            text.font = NSFont.systemFont(ofSize: 12)
            text.lineBreakMode = .byTruncatingTail
            newCell.addSubview(text)
            newCell.textField = text
            return newCell
        }()
        let items = tableView === leftTableView ? enabled : allItems
        guard row < items.count else { return nil }
        let item = items[row]
        cell.textField?.stringValue = item.title
        // 右侧已加入左侧的项置灰，提示无需重复添加
        let dimmed = tableView !== leftTableView && enabled.contains(item)
        cell.textField?.textColor = dimmed || item.isSeparator ? .secondaryLabelColor : .labelColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        if tableView === leftTableView {
            selectedLeft = tableView.selectedRow
        } else {
            selectedRight = tableView.selectedRow
        }
    }

    // MARK: - 拖拽排序（仅左侧列表）

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tableView === leftTableView, row < enabled.count else { return nil }
        return enabled[row].rawValue as NSString
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard tableView === leftTableView, operation == .above else { return [] }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard tableView === leftTableView,
              let name = info.draggingPasteboard.string(forType: .string),
              let item = ContextMenuItemID(rawValue: name),
              let from = enabled.firstIndex(of: item) else { return false }
        enabled.remove(at: from)
        var target = row
        if from < row { target -= 1 }
        target = max(0, min(enabled.count, target))
        enabled.insert(item, at: target)
        selectedLeft = target
        save()
        return true
    }

    // MARK: - 按钮动作

    @objc private func addItem() {
        guard allItems.indices.contains(selectedRight) else { return }
        let item = allItems[selectedRight]
        // 已在左侧的项不重复添加
        guard !enabled.contains(item) else { return }
        enabled.append(item)
        selectedLeft = enabled.count - 1
        save()
    }

    @objc private func removeItem() {
        guard enabled.indices.contains(selectedLeft) else { return }
        enabled.remove(at: selectedLeft)
        selectedLeft = max(0, min(selectedLeft, enabled.count - 1))
        save()
    }

    @objc private func moveItemUp() {
        guard selectedLeft > 0, selectedLeft < enabled.count else { return }
        enabled.swapAt(selectedLeft, selectedLeft - 1)
        selectedLeft -= 1
        save()
    }

    @objc private func moveItemDown() {
        guard selectedLeft >= 0, selectedLeft < enabled.count - 1 else { return }
        enabled.swapAt(selectedLeft, selectedLeft + 1)
        selectedLeft += 1
        save()
    }

    @objc private func resetItems() {
        AppSettings.resetContextMenuItems()
        enabled = AppSettings.contextMenuItems
        selectedLeft = 0
        selectedRight = 0
        save()
    }

    @objc private func tableDoubleClicked(_ tableView: NSTableView) {
        if tableView === rightTableView { addItem() }
    }
}

/// 偏好设置「常规」里的快速访问列表：调整顺序、添加 / 移除目录
final class QuickAccessSettingsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var items: [QuickAccessItem] = []
    private let addButton = NSButton()
    private let removeButton = NSButton()
    private let upButton = NSButton()
    private let downButton = NSButton()
    private let resetButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "名称"
        nameColumn.width = 150
        nameColumn.minWidth = 100
        let pathColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        pathColumn.title = "路径"
        pathColumn.width = 300
        pathColumn.minWidth = 160
        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(pathColumn)
        tableView.rowHeight = 21
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        scrollView.documentView = tableView
        addSubview(scrollView)

        configure(addButton, title: "添加目录…", action: #selector(addFolder), width: 100)
        configure(removeButton, title: "移除", action: #selector(removeSelected), width: 56)
        configure(upButton, title: "上移", action: #selector(moveItemUp), width: 56)
        configure(downButton, title: "下移", action: #selector(moveItemDown), width: 56)
        configure(resetButton, title: "恢复默认", action: #selector(restoreDefaults), width: 88)
        [addButton, removeButton, upButton, downButton, resetButton].forEach { addSubview($0) }

        reload(selecting: 0)
    }

    private func configure(_ button: NSButton, title: String, action: Selector, width: CGFloat) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        button.frame = NSRect(x: 0, y: 0, width: width, height: 26)
    }

    override func layout() {
        super.layout()
        let buttonHeight: CGFloat = 26
        let gap: CGFloat = 6
        scrollView.frame = NSRect(x: 0, y: buttonHeight + gap, width: bounds.width,
                                  height: max(0, bounds.height - buttonHeight - gap))
        // 表格宽度跟随滚动区，路径列自动填满右侧空白
        let contentWidth = scrollView.contentSize.width
        if contentWidth > 0 {
            if tableView.frame.width != contentWidth {
                var frame = tableView.frame
                frame.size.width = contentWidth
                tableView.frame = frame
            }
            // 「路径」列吃掉右侧剩余空间，避免表格右边留白
            if let nameColumn = tableView.tableColumns.first, let pathColumn = tableView.tableColumns.last {
                let target = max(pathColumn.minWidth, contentWidth - nameColumn.width)
                if abs(pathColumn.width - target) > 0.5 { pathColumn.width = target }
            }
        }
        var x: CGFloat = 0
        for button in [addButton, removeButton, upButton, downButton, resetButton] {
            button.frame = NSRect(x: x, y: 0, width: button.frame.width, height: buttonHeight)
            x += button.frame.width + 8
        }
    }

    // MARK: - 数据

    private func reload(selecting index: Int?) {
        items = AppSettings.quickAccessItems
        tableView.reloadData()
        if let index, index >= 0, index < items.count {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else {
            tableView.deselectAll(nil)
        }
        updateButtons()
    }

    /// 写回设置（会通知侧边栏刷新）
    private func persist(selecting index: Int?) {
        AppSettings.quickAccessItems = items
        reload(selecting: index)
    }

    private func updateButtons() {
        let row = tableView.selectedRow
        removeButton.isEnabled = row >= 0 && row < items.count
        upButton.isEnabled = row > 0
        downButton.isEnabled = row >= 0 && row < items.count - 1
    }

    // MARK: - 按钮

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "添加到快速访问"
        panel.message = "选择要显示在侧边栏「快速访问」里的文件夹"
        panel.prompt = "添加"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK else { return }
            var lastIndex: Int?
            for url in panel.urls {
                let path = url.standardizedFileURL.path
                guard !self.items.contains(where: { $0.path == path }) else { continue }
                let title = url.lastPathComponent.isEmpty ? path : url.lastPathComponent
                self.items.append(QuickAccessItem(title: title, path: path, icon: "folder"))
                lastIndex = self.items.count - 1
            }
            if lastIndex != nil { self.persist(selecting: lastIndex) }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    @objc private func removeSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        items.remove(at: row)
        persist(selecting: min(row, items.count - 1))
    }

    @objc private func moveItemUp() {
        let row = tableView.selectedRow
        guard row > 0, row < items.count else { return }
        items.swapAt(row, row - 1)
        persist(selecting: row - 1)
    }

    @objc private func moveItemDown() {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count - 1 else { return }
        items.swapAt(row, row + 1)
        persist(selecting: row + 1)
    }

    @objc private func restoreDefaults() {
        items = AppSettings.defaultQuickAccessItems
        persist(selecting: 0)
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count, let tableColumn else { return nil }
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = tableColumn.identifier
            let field = NSTextField(labelWithString: "")
            field.font = NSFont.systemFont(ofSize: 12)
            field.lineBreakMode = .byTruncatingMiddle
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        let item = items[row]
        let isName = tableColumn.identifier.rawValue == "name"
        cell.textField?.stringValue = isName ? item.title : item.path
        cell.textField?.textColor = isName ? .labelColor : .secondaryLabelColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }
}

/// 偏好设置里的分组卡片背景（圆角、细边框）
final class SettingCardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var controllers: [NSWindow: MainViewController] = [:]
    /// 主窗口（「新窗口打开」弹出的独立单窗口不算）
    private weak var mainWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private weak var bookmarksMenuRef: NSMenu?
    private weak var workspacesMenuRef: NSMenu?
    private var lastHorizontalSwipe = Date.distantPast
    private var globalScreenshotMonitor: Any?
    private var screenshotHotKeyRef: EventHotKeyRef?
    private var screenshotHotKeyHandler: EventHandlerRef?
    private var statusItem: NSStatusItem?
    private var iconSliders: [NSSlider] = []
    private var textSliders: [NSSlider] = []
    private var iconValueLabels: [NSTextField] = []
    private var textValueLabels: [NSTextField] = []
    private var modifierRecorder: ModifierRecorder?
    private var screenshotRecorder: ShortcutRecorder?
    private var undoRecorder: ShortcutRecorder?
    private var undoLimitSlider: NSSlider?
    private var undoLimitLabel: NSTextField?
    private weak var undoMenuItem: NSMenuItem?
    private var screenshotDirectoryLabel: NSTextField?
    /// 「布局」页的单选按钮，切换时手动互斥
    private var layoutRadios: [NSButton] = []
    /// 偏好设置的标签容器，布局变化时用它重建「外观」「壁纸」页
    private weak var preferencesTabs: NSTabView?
    /// 只有用户从“彻底退出”入口调用时才允许真正结束进程
    private var allowTermination = false
    /// 系统正在关机/重启：此时必须放行退出，否则 macOS 会判定本 App 阻止关机
    private var isSystemShuttingDown = false
    /// Finder 双击压缩包时，openFile / openFiles 可能都回调；用短时间窗去重，避免重复开窗。
    private var lastOpenedArchive: (path: String, at: Date)?

    func application(_ application: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }

    // MARK: - Finder 双击压缩包：交给内置 7-Zip 浏览窗口

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { openArchiveFromFinder($0) }
    }

    func application(_ application: NSApplication, openFile filename: String) -> Bool {
        openArchiveFromFinder(URL(fileURLWithPath: filename))
        return true
    }

    private func openArchiveFromFinder(_ url: URL) {
        guard SevenZip.isArchive(url) else { return }
        let now = Date()
        if let last = lastOpenedArchive, last.path == url.path,
           now.timeIntervalSince(last.at) < 3 { return }
        lastOpenedArchive = (url.path, now)

        let browser = ArchiveBrowserController(archive: url)
        browser.open { ok, message in
            guard !ok else { return }
            let alert = NSAlert()
            alert.messageText = "无法打开压缩包"
            alert.informativeText = message.isEmpty ? "7-Zip 无法读取该文件。" : message
            alert.alertStyle = .warning
            alert.icon = SevenZipIcon.archive
            alert.runModal()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 全局深色外观，参考 QSpace Pro 的深色主题（菜单/弹窗/列表统一适配）
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // 触发一次右键菜单迁移，确保新版本新增的菜单项对老用户可见
        _ = AppSettings.contextMenuItems
        buildMainMenu()
        _ = createWindow()
        NSApp.activate(ignoringOtherApps: true)

        // 系统关机/重启/注销时放行真正退出，避免「XSpace 阻止了关机」。
        // willPowerOffNotification 覆盖关机与重启；注销走 currentEvent 判断（见下）。
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillPowerOff),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )

        // 自动化/排查用：设置 XSPACE_OPEN_PREFS=1 可直接打开偏好设置，
        // 并用 XSPACE_PREFS_TAB=appearance|wallpaper|layout|general|contextMenu 定位到指定标签页。
        if ProcessInfo.processInfo.environment["XSPACE_OPEN_PREFS"] != nil {
            showPreferences()
        }
        // 自动化/排查用：XSPACE_OPEN_BULK_RENAME=1 启动即打开批量重命名窗口
        if ProcessInfo.processInfo.environment["XSPACE_OPEN_BULK_RENAME"] != nil {
            currentController().openBulkRename()
        }
        NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            // Windows 惯例：侧键 4（X1）后退，侧键 5（X2）前进
            if event.buttonNumber == 3 {
                self.currentController().goBack()
                return nil
            }
            if event.buttonNumber == 4 {
                self.currentController().goForward()
                return nil
            }
            return event
        }

        // 触控板双指横向滑动：与浏览器/资源管理器一致的历史导航
        NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self = self else { return event }
            let dx = event.deltaX
            guard abs(dx) > 4, abs(dx) > abs(event.deltaY) * 2,
                  Date().timeIntervalSince(self.lastHorizontalSwipe) > 0.8,
                  !self.isEditingTextInput() else { return event }
            self.lastHorizontalSwipe = Date()
            let controller = self.currentController()
            if dx > 0 { controller.goBack() } else { controller.goForward() }
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let controller = self.currentController()
            // 焦点是否落在「文件浏览器」区域（白名单）。所有会改写文件/导航的快捷键都要求它为真。
            // 任何输入框、字段编辑器、弹窗（批量重命名/偏好设置）聚焦时一律为 false，
            // 事件交还系统 → 输入框能正常用 ⌘C/⌘V 复制粘贴文字。
            let inFileBrowser = self.isFileBrowserFocused()

            // 文字编辑态（就地重命名 / 路径栏 / 批量重命名输入框等）：
            // ⌘/⌃ + C/X/V/A 主动派发给字段编辑器的同名 action。
            //
            // 背景：用 Windows 键盘并在系统「修饰键」里把 Command 与 Control 互换后，
            // 文件快捷键仍正常（本监听按 modifierFlags 判断），但 NSTextView 依赖 AppKit
            // 的键位绑定层把按键翻译成 copy:/paste:，这层在某些键盘映射组合下不会把它
            // 识别成系统复制/粘贴 —— 于是出现「右键菜单复制粘贴有效、快捷键无效」。
            // 这里直接调用 NSTextView 的 action（与右键菜单完全相同的路径），
            // 并同时接受 command / control 修饰键，任何键位映射下都能可靠编辑文字。
            if self.isEditingTextInput(), !flags.intersection([.command, .control]).isEmpty {
                let editor: NSTextView? = {
                    let responder = NSApp.keyWindow?.firstResponder
                    if let textView = responder as? NSTextView { return textView }
                    if let textField = responder as? NSTextField {
                        return textField.currentEditor() as? NSTextView
                    }
                    return nil
                }()
                if let editor {
                    switch event.charactersIgnoringModifiers ?? "" {
                    case "c": editor.copy(nil); return nil
                    case "x": editor.cut(nil); return nil
                    case "v": editor.paste(nil); return nil
                    case "a":
                        // ⌘A 全选；⌃A 在 NSTextView 里是「移到行首」，保留系统原行为
                        if flags.contains(.command) { editor.selectAll(nil); return nil }
                    default: break
                    }
                }
            }

            // 自定义撤销快捷键（默认 ⌘Z）。撤销对全 App 生效，但仍不能在文字编辑态抢事件。
            let undoShortcut = AppSettings.undoShortcut
            if event.keyCode == undoShortcut.keyCode,
               flags.intersection([.command, .option, .shift, .control]).rawValue == undoShortcut.modifiers,
               inFileBrowser {
                controller.undo()
                return nil
            }
            if flags.contains(.command), inFileBrowser {
                switch event.charactersIgnoringModifiers {
                case "[": controller.goBack(); return nil
                case "]": controller.goForward(); return nil
                case "l": controller.goToPath(); return nil
                case "f": controller.focusSearch(); return nil
                // 文件操作快捷键集中在这里处理（已从菜单 keyEquivalent 移除）。
                // inFileBrowser 为 true 才走到这里：焦点确实在文件列表，⌘C/⌘V/⌘X/⌘A 只作用于文件。
                case "c": controller.copySelected(); return nil
                case "x": controller.cutSelected(); return nil
                case "v": controller.pasteHere(); return nil
                case "a": controller.selectAll(); return nil
                default: break
                }
                if flags.contains(.shift), event.charactersIgnoringModifiers == "N" {
                    controller.newFolder()
                    return nil
                }
            }
            if event.keyCode == 144, inFileBrowser { // F2 重命名
                controller.renameSelected()
                return nil
            }
            if (event.keyCode == 51 || event.keyCode == 117), inFileBrowser { // Delete / Forward Delete 移到废纸篓
                controller.trashSelectedWithoutConfirm()
                return nil
            }
            return event
        }

        // 注册系统级全局截图热键（Carbon 热键不依赖辅助功能权限，其他 App 前台也能触发）
        registerScreenshotHotKey()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenshotShortcutDidChange),
            name: .xspaceShortcutChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(undoSettingsDidChange),
            name: .xspaceUndoSettingsChanged,
            object: nil
        )

        // 常驻后台：菜单栏状态图标，关掉主窗口后仍可截图 / 重开窗口 / 设置 / 退出
        setupStatusItem()

    }

    // MARK: - 全局截图热键（Carbon RegisterEventHotKey）

    /// 当前按键是否应该完全交给界面自己处理（正在编辑文字、或有弹窗/面板开着）。
    ///
    /// 关键点：弹窗里的 NSTextField 获得焦点后，第一响应者是它的字段编辑器（NSTextView），
    /// 而不是 NSTextField 本身；另外 runModal 期间 keyWindow 可能不是主窗口。
    /// 只看 `firstResponder is NSTextField` 会漏判，导致 Delete 被「删除文件」的快捷键吞掉，
    /// 表现为重命名 / 新建文件夹时文字删不掉（文件反而进了废纸篓）。
    func isEditingTextInput() -> Bool {
        if NSApp.modalWindow != nil { return true }
        if NSApp.keyWindow?.attachedSheet != nil || NSApp.mainWindow?.attachedSheet != nil { return true }
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextField || responder is NSTextView
    }

    /// 焦点是否确实落在「文件列表」上（列表视图 / 图标视图 / 侧边栏 / 窗格容器）。
    /// 文件操作快捷键（⌘C/⌘V/⌘X/⌘A）用白名单判断：只有焦点在文件浏览器区域时才拦截，
    /// 其余任何情况（重命名框、路径栏、弹窗输入框、字段编辑器等）一律交还给系统，
    /// 从根本上避免「在输入框里框选文字按 ⌘C，却复制了文件 / 粘贴出文件路径」。
    func isFileBrowserFocused() -> Bool {
        guard let window = NSApp.keyWindow else { return false }
        // 弹窗 / 偏好设置 / 批量重命名窗口都不是文件浏览器主窗口
        guard window.contentViewController is MainViewController else { return false }
        // 正在编辑文字（含字段编辑器 NSTextView）时，焦点不属于文件列表
        if isEditingTextInput() { return false }
        guard let responder = window.firstResponder else { return false }
        return responder is PaneTableView || responder is IconCollectionView
            || responder is PaneContainerView || responder is NSOutlineView
            || responder is NSScrollView
    }

    private func registerScreenshotHotKey() {
        if let ref = screenshotHotKeyRef {
            UnregisterEventHotKey(ref)
            screenshotHotKeyRef = nil
        }
        if let handler = screenshotHotKeyHandler {
            RemoveEventHandler(handler)
            screenshotHotKeyHandler = nil
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, _ -> OSStatus in
            DispatchQueue.main.async { appDelegate.takeScreenshotFromHotKey() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &screenshotHotKeyHandler)

        let shortcut = AppSettings.screenshotShortcut
        var carbonMods: UInt32 = 0
        let flags = NSEvent.ModifierFlags(rawValue: shortcut.modifiers)
        if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if flags.contains(.control) { carbonMods |= UInt32(controlKey) }
        let hotKeyID = EventHotKeyID(signature: OSType(0x58535043), id: UInt32(1)) // 'XSPC'
        RegisterEventHotKey(UInt32(shortcut.keyCode), carbonMods, hotKeyID,
                            GetApplicationEventTarget(), 0, &screenshotHotKeyRef)
    }

    @objc private func screenshotShortcutDidChange() {
        registerScreenshotHotKey()
    }

    /// 撤销快捷键或步数变化：菜单、录制控件与数值标签同步刷新
    @objc private func undoSettingsDidChange() {
        undoMenuItem?.keyEquivalent = AppSettings.undoShortcut.menuKey
        undoMenuItem?.keyEquivalentModifierMask = AppSettings.undoShortcut.flags
        undoRecorder?.refresh()
        screenshotRecorder?.refresh()
        undoLimitSlider?.intValue = Int32(AppSettings.undoLimit)
        undoLimitLabel?.stringValue = "\(AppSettings.undoLimit)"
    }

    /// 全局热键回调入口：录制快捷键时不触发截图
    @objc func takeScreenshotFromHotKey() {
        if NSApp.keyWindow?.firstResponder is ShortcutRecorder { return }
        takeScreenshot()
    }

    // MARK: - 菜单栏常驻图标

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "XSpace")
                ?? NSImage(systemSymbolName: "folder", accessibilityDescription: "XSpace")
            button.image = image
            button.image?.isTemplate = true
            button.toolTip = "XSpace"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "显示 XSpace", action: #selector(showMainWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "截图", action: #selector(takeScreenshot), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "隐藏到后台", action: #selector(hideToBackground), keyEquivalent: "").target = self
        menu.addItem(withTitle: "显示 XSpace", action: #selector(showMainWindow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "偏好设置…", action: #selector(showPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "彻底退出 XSpace", action: #selector(reallyQuit), keyEquivalent: "").target = self
        item.menu = menu
        statusItem = item
    }

    @objc func showMainWindow() {
        if let window = mainWindow ?? controllers.keys.first {
            window.makeKeyAndOrderFront(nil)
        } else {
            _ = createWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func matchesScreenshotShortcut(_ event: NSEvent) -> Bool {
        let shortcut = AppSettings.screenshotShortcut
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        return event.keyCode == shortcut.keyCode && flags.rawValue == shortcut.modifiers
    }

    @objc private func takeScreenshot() {
        if !ScreenshotEditorController.shared.start() {
            Dialog.alert(title: "截图失败", message: "无法截取屏幕，请检查“屏幕录制”权限。")
        }
    }

    /// 收到系统关机/重启通知：标记后放行真正退出，绝不阻止系统关机。
    @objc private func systemWillPowerOff() {
        isSystemShuttingDown = true
    }

    /// ⌘Q / Dock 退出 / 点红叉都改为隐藏到后台，保证全局截图热键常驻；
    /// 但系统关机/重启/注销必须放行，否则会出现「XSpace 阻止了关机」并卡住关机流程。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 收到 willPowerOffNotification（关机/重启）或用户点了“彻底退出”：立即退出
        if allowTermination || isSystemShuttingDown { return .terminateNow }
        // 注销（logout）不会发 willPowerOffNotification，但此时没有键盘/鼠标事件触发退出，
        // 而用户主动 ⌘Q 会带 keyDown 事件。借此区分：无用户事件的退出请求视为系统发起，放行。
        if !allowTermination, sender.currentEvent == nil { return .terminateNow }
        hideToBackground()
        return .terminateCancel
    }

    /// 隐藏主窗口与偏好设置窗口，但不关闭截图浮层/图钉，进程继续运行
    @objc func hideToBackground() {
        for window in NSApp.windows {
            if window === preferencesWindow || window.contentViewController is MainViewController {
                window.orderOut(nil)
            }
        }
        NSApp.hide(nil)
    }

    @objc private func reallyQuit() {
        allowTermination = true
        NSApp.terminate(nil)
    }

    /// 常驻后台：关闭最后一个窗口不退出应用
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 点击 Dock 图标时若没有可见窗口则重新显示主窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    /// 主窗口红叉关闭时改为隐藏，保留状态并继续常驻后台；
    /// 「新窗口打开」的独立窗口则真正关闭并释放，不影响主程序。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender.identifier?.rawValue == "XSpaceStandalone" {
            return true
        }
        sender.orderOut(nil)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "XSpaceStandalone" else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        controllers.removeValue(forKey: window)
    }

    // MARK: - 窗口

    /// 创建窗口。
    /// - Parameters:
    ///   - layout: 固定布局；nil 表示跟随全局设置，`.single` 用于「新窗口打开」的独立单窗口
    ///   - url: 首个窗格打开的目录
    @discardableResult
    private func createWindow(layout: PaneLayout? = nil, at url: URL? = nil) -> MainViewController {
        let isStandalone = (layout == .single)
        let controller = MainViewController(layout: layout, initialURL: url, standalone: isStandalone)
        let size = isStandalone ? NSSize(width: 1040, height: 700) : NSSize(width: 1280, height: 760)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "XSpace"
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = false
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = controller
        window.minSize = isStandalone ? NSSize(width: 620, height: 420) : NSSize(width: 900, height: 520)
        window.center()

        if isStandalone {
            window.identifier = NSUserInterfaceItemIdentifier("XSpaceStandalone")
            // 相对主窗口错开一点，避免完全重叠
            if let mainWindow {
                let base = mainWindow.frame
                window.setFrameOrigin(NSPoint(x: base.origin.x + 48, y: base.origin.y - 48))
            }
        } else {
            mainWindow = window
        }

        // 右键「新窗口打开」统一交给 AppDelegate 弹出独立单窗口
        controller.onOpenInNewWindow = { [weak self] target in
            self?.createWindow(layout: .single, at: target)
        }

        window.makeKeyAndOrderFront(nil)
        controllers[window] = controller
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        return controller
    }

    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        controllers[window]?.activePane.activate()
    }

    private func currentController() -> MainViewController {
        if let window = NSApp.keyWindow, let controller = controllers[window] { return controller }
        return controllers.values.first!
    }

    // MARK: - 菜单构建

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu()
        mainMenu.addItem(appMenuItem)

        for menu in [fileMenu(), editMenu(), viewMenu(), goMenu(), bookmarksMenu(), workspacesMenu(), windowMenu(), helpMenu()] {
            let item = NSMenuItem()
            item.submenu = menu
            mainMenu.addItem(item)
        }
        NSApp.mainMenu = mainMenu
    }

    private func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "关于 XSpace", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "偏好设置…", action: #selector(showPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "隐藏 XSpace", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h").target = NSApp
        menu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").target = NSApp
        menu.addItem(.separator())
        menu.addItem(withTitle: "关闭到后台（截图仍可用）", action: #selector(hideToBackground), keyEquivalent: "").target = self
        menu.addItem(withTitle: "彻底退出 XSpace", action: #selector(reallyQuit), keyEquivalent: "").target = self
        return menu
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "文件")
        add("新建窗口", #selector(newWindow), "n", to: menu)
        add("新建文件夹", #selector(newFolder), "N", to: menu)
        menu.addItem(.separator())
        add("打开", #selector(openSelected), "o", to: menu)
        add("在新窗格中打开", #selector(openInOtherPane), "o", to: menu, modifiers: [.command, .option])
        menu.addItem(.separator())
        // 这四项不再注册为菜单 keyEquivalent：菜单快捷键是全局匹配的，
        // 弹窗/输入框获得焦点时按 ⌘V/⌘C 会抢先触发文件粘贴/复制，导致
        // 「重命名窗口粘贴成文件」「框选文字复制到文件路径」。
        // 改由 applicationDidFinishLaunching 里的全局 keyDown 监听按焦点分发。
        add("剪切    ⌘X", #selector(cutSelected), "", to: menu)
        add("复制    ⌘C", #selector(copySelected), "", to: menu)
        add("粘贴到此处    ⌘V", #selector(pasteHere), "", to: menu)
        add("全选    ⌘A", #selector(selectAll), "", to: menu)
        menu.addItem(.separator())
        add("重命名", #selector(renameSelected), "", to: menu)
        add("移到废纸篓", #selector(trashSelected), "", to: menu)
        add("在终端打开", #selector(openInTerminal), "", to: menu)
        menu.addItem(.separator())
        add("关闭窗口", #selector(NSWindow.close), "w", to: menu, target: nil)
        return menu
    }

    private func editMenu() -> NSMenu {
        let menu = NSMenu(title: "编辑")
        undoMenuItem = add("撤销", #selector(undo), AppSettings.undoShortcut.menuKey,
                           to: menu, modifiers: AppSettings.undoShortcut.flags)
        menu.addItem(.separator())
        add("返回", #selector(goBack), "[", to: menu)
        add("前进", #selector(goForward), "]", to: menu)
        add("上层文件夹", #selector(goUp), "↑", to: menu)
        menu.addItem(.separator())
        add("查找", #selector(focusSearch), "f", to: menu)
        add("反向选择", #selector(invertSelection), "", to: menu)
        add("拷贝路径", #selector(copyPath), "", to: menu)
        menu.addItem(.separator())
        add("批量重命名…", #selector(bulkRename), "r", to: menu, modifiers: [.command, .option])
        return menu
    }

    private func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "显示")
        add("刷新", #selector(refresh), "r", to: menu)
        add("显示隐藏文件", #selector(toggleHiddenFiles), ".", to: menu)
        menu.addItem(.separator())
        add("图标", #selector(showIconView), "1", to: menu, modifiers: [.command])
        add("列表", #selector(showListView), "2", to: menu, modifiers: [.command])
        menu.addItem(.separator())
        add("按名称排序", #selector(sortByName), "", to: menu)
        add("按修改日期排序", #selector(sortByModified), "", to: menu)
        add("按大小排序", #selector(sortBySize), "", to: menu)
        add("按类型排序", #selector(sortByKind), "", to: menu)
        menu.addItem(.separator())
        add("显示/隐藏侧边栏", #selector(toggleSidebar), "s", to: menu, modifiers: [.command, .option])
        add("显示简介", #selector(showInfo), "i", to: menu, modifiers: [.command])
        return menu
    }

    private func goMenu() -> NSMenu {
        let menu = NSMenu(title: "前往")
        add("个人", #selector(goHome), "", to: menu)
        add("桌面", #selector(goDesktop), "", to: menu)
        add("文稿", #selector(goDocuments), "", to: menu)
        add("下载", #selector(goDownloads), "", to: menu)
        add("应用程序", #selector(goApplications), "", to: menu)
        add("根目录", #selector(goRoot), "", to: menu)
        menu.addItem(.separator())
        add("上层文件夹", #selector(goUp), "↑", to: menu)
        add("前往路径…", #selector(goToPath), "l", to: menu)
        return menu
    }

    private func bookmarksMenu() -> NSMenu {
        let menu = NSMenu(title: "书签")
        menu.delegate = self
        bookmarksMenuRef = menu
        add("添加当前文件夹为书签", #selector(addBookmark), "", to: menu)
        menu.addItem(.separator())
        return menu
    }

    private func workspacesMenu() -> NSMenu {
        let menu = NSMenu(title: "工作区")
        menu.delegate = self
        workspacesMenuRef = menu
        add("保存当前工作区…", #selector(saveWorkspace), "", to: menu)
        add("重置为默认布局", #selector(resetPanes), "", to: menu)
        menu.addItem(.separator())
        return menu
    }

    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "窗口")
        add("最小化", #selector(NSWindow.miniaturize(_:)), "m", to: menu, target: nil)
        add("缩放", #selector(NSWindow.zoom(_:)), "", to: menu, target: nil)
        menu.addItem(.separator())
        add("前置全部窗口", #selector(NSApplication.arrangeInFront(_:)), "", to: menu, target: NSApp)
        menu.addItem(.separator())
        for i in 0..<PaneLayout.maxPanes {
            let item = NSMenuItem(title: "聚焦窗格 \(i + 1)", action: #selector(focusPane(_:)), keyEquivalent: "\(i + 1)")
            item.target = self
            item.tag = i
            item.keyEquivalentModifierMask = [.command]
            menu.addItem(item)
        }
        return menu
    }

    private func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "帮助")
        add("使用说明", #selector(showHelp), "", to: menu)
        add("关于 XSpace", #selector(showAbout), "", to: menu)
        return menu
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, _ key: String, to menu: NSMenu, modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target ?? self
        menu.addItem(item)
        return item
    }

    // MARK: - NSMenuDelegate（动态书签 / 工作区）

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === bookmarksMenuRef {
            menu.items.filter { $0.tag == 700 }.forEach { menu.removeItem($0) }
            for (index, url) in AppSettings.bookmarks.enumerated() {
                let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openBookmark(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = url
                item.tag = 700 + index
                menu.addItem(item)
            }
        } else if menu === workspacesMenuRef {
            menu.items.filter { $0.tag >= 800 }.forEach { menu.removeItem($0) }
            for (index, space) in AppSettings.workspaces.enumerated() {
                let item = NSMenuItem(title: space.name, action: #selector(openWorkspace(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = space
                item.tag = 800 + index
                menu.addItem(item)
            }
        }
    }

    // MARK: - 菜单项校验

    /// 这些是文件管理器主窗口专属操作。当批量重命名、偏好设置等窗口为 keyWindow 时
    /// 必须禁用它们，否则系统菜单的键位匹配（如 ⌘V「粘贴到此处」）会抢在输入框前面
    /// 触发文件粘贴，而不是让文字输入框正常粘贴文本。
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let sel = menuItem.action else { return true }
        let paneOnly: Set<Selector> = [
            #selector(undo), #selector(newFolder), #selector(openSelected),
            #selector(openInOtherPane), #selector(cutSelected), #selector(copySelected),
            #selector(pasteHere), #selector(selectAll), #selector(invertSelection),
            #selector(renameSelected), #selector(trashSelected), #selector(openInTerminal),
            #selector(copyPath), #selector(goBack), #selector(goForward), #selector(goUp),
            #selector(refresh), #selector(toggleHiddenFiles), #selector(focusSearch),
            #selector(toggleSidebar), #selector(sortByName), #selector(sortByModified),
            #selector(sortBySize), #selector(sortByKind), #selector(goToPath),
        ]
        if paneOnly.contains(sel) {
            // 文字输入态（内联重命名/路径编辑/弹窗，含主窗口内的输入框）时禁用，
            // 让 ⌘V/⌘C/⌘X/⌘A 等交给输入框处理，而不是触发文件操作。
            if isEditingTextInput() { return false }
            // 只有文件管理器主窗口处于活跃状态时才允许这些操作；
            // 批量重命名/偏好设置等窗口（contentViewController 不是 MainViewController）禁用。
            guard let key = NSApp.keyWindow, key.contentViewController is MainViewController else {
                return false
            }
            // 撤销项还要结合撤销栈是否为空
            if sel == #selector(undo) { return FileUndoStack.shared.canUndo }
        }
        return true
    }

    // MARK: - 菜单动作

    @objc func newWindow() { createWindow() }
    @objc func undo() { currentController().undo() }
    @objc func newFolder() { currentController().newFolder() }
    @objc func openSelected() { currentController().openSelected() }
    @objc func openInOtherPane() { currentController().activePane.openInOtherPane() }
    @objc func cutSelected() { currentController().cutSelected() }
    @objc func copySelected() { currentController().copySelected() }
    @objc func pasteHere() { currentController().pasteHere() }
    @objc func selectAll() { currentController().selectAll() }
    @objc func invertSelection() { currentController().invertSelection() }
    @objc func renameSelected() { currentController().renameSelected() }
    @objc func bulkRename() { currentController().openBulkRename() }
    @objc func trashSelected() { currentController().trashSelected() }
    @objc func openInTerminal() { currentController().activePane.openInTerminal() }
    @objc func copyPath() { currentController().activePane.copyPath() }
    @objc func showInfo() { currentController().activePane.showInfo() }
    @objc func goBack() { currentController().goBack() }
    @objc func goForward() { currentController().goForward() }
    @objc func goUp() { currentController().goUp() }
    @objc func refresh() { currentController().refresh() }
    @objc func toggleHiddenFiles() { currentController().toggleHiddenFiles() }
    @objc func focusSearch() { currentController().focusSearch() }
    @objc func toggleSidebar() { currentController().toggleSidebar() }
    @objc func sortByName() { currentController().sortByName() }
    @objc func sortByModified() { currentController().sortByModified() }
    @objc func sortBySize() { currentController().sortBySize() }
    @objc func sortByKind() { currentController().sortByKind() }
    @objc func goToPath() { currentController().goToPath() }
    @objc func goHome() { currentController().goHome() }
    @objc func goDesktop() { currentController().goDesktop() }
    @objc func goDocuments() { currentController().goDocuments() }
    @objc func goDownloads() { currentController().goDownloads() }
    @objc func goApplications() { currentController().goApplications() }
    @objc func goRoot() { currentController().goRoot() }
    @objc func addBookmark() { currentController().addBookmark() }
    @objc func saveWorkspace() { currentController().saveWorkspace() }
    @objc func resetPanes() { currentController().resetPanes() }
    @objc func focusPane(_ item: NSMenuItem) { currentController().focusPane(at: item.tag) }

    @objc func showIconView() { setActiveMode(.icon) }
    @objc func showListView() { setActiveMode(.list) }
    private func setActiveMode(_ mode: PaneViewMode) {
        let pane = currentController().activePane!
        if pane.paneViewMode != mode { pane.toggleViewMode() }
    }

    @objc func openBookmark(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL else { return }
        currentController().activePane.navigate(to: url)
    }

    @objc func openWorkspace(_ item: NSMenuItem) {
        guard let space = item.representedObject as? WorkspaceSnapshot else { return }
        currentController().restoreWorkspace(space)
    }

    /// 版本号（Info.plist 的 CFBundleShortVersionString）
    static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short)（Build \(build)）"
    }

    @objc func showAbout() {
        Dialog.alert(
            title: "XSpace",
            message: "一个 Mac 上轻量级别的多窗口文件管理器。\n集成了轻量级别的截图以及 7-ZIP 功能。\n版本 \(Self.appVersion)"
        )
    }

    @objc func showHelp() {
        Dialog.alert(
            title: "使用说明",
            message: "布局：一个窗口内可显示 1~4 个窗格（偏好设置 → 布局 里切换），每个窗格独立目录与历史；「外观」「壁纸」里的分窗格设置会自动跟随窗格数量。\n\n导航：⌘[ 后退，⌘] 前进，⌘↑ 上层，⌘L 前往路径；鼠标侧键 X1/X2 对应后退/前进；触控板左右滑动同样有效。\n\n操作：双击打开，F2 重命名，Delete 直接移到废纸篓，⌘C/⌘X/⌘V 复制/剪切/粘贴；在窗格之间拖拽文件默认移动，按住 Option 拖拽则为复制。\n\n右键：打开、新窗口打开、新建文件夹、重命名、剪切、复制、粘贴、废纸篓、拷贝路径、显示简介。"
        )
    }

    @objc func showPreferences() {
        // 复用已经创建的偏好设置窗口（关闭后窗口对象仍然保留）
        if let preferencesWindow {
            // 期间布局可能变过，重新生成「外观」「壁纸」页保证窗格行数正确
            rebuildPaneDependentTabs()
            preferencesWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        // 代码创建的窗口默认 isReleasedWhenClosed = true，关闭时会被释放，
        // 之后再访问 preferencesWindow 就会访问已释放对象导致崩溃，这里必须关掉。
        window.isReleasedWhenClosed = false
        window.title = "偏好设置"
        window.center()

        let tabs = NSTabView(frame: NSRect(x: 0, y: 0, width: 560, height: 560))
        tabs.addTabViewItem(generalTabItem())
        tabs.addTabViewItem(shortcutsTabItem())
        tabs.addTabViewItem(layoutTabItem())
        tabs.addTabViewItem(appearanceTabItem())
        tabs.addTabViewItem(wallpaperTabItem())
        tabs.addTabViewItem(contextMenuTabItem())
        tabs.addTabViewItem(sevenZipTabItem())
        window.contentView = tabs

        preferencesTabs = tabs
        preferencesWindow = window
        if let tabID = ProcessInfo.processInfo.environment["XSPACE_PREFS_TAB"],
           let target = tabs.tabViewItems.first(where: { ($0.identifier as? String) == tabID }) {
            tabs.selectTabViewItem(target)
        }
        updatePreferenceLabels()
        window.makeKeyAndOrderFront(nil)
    }

    private func contextMenuTabItem() -> NSTabViewItem {
        let view = ContextMenuSettingsView(frame: NSRect(x: 0, y: 0, width: 560, height: 520))
        let item = NSTabViewItem(identifier: "contextMenu")
        item.label = "右键菜单"
        item.view = view
        return item
    }

    // MARK: - 7-ZIP 设置页

    private func sevenZipTabItem() -> NSTabViewItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 520))
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

        // 集成状态卡片
        view.addSubview(SettingCardView(frame: NSRect(x: 16, y: 386, width: 528, height: 114)))
        let statusTitle = makeLabel("7-ZIP", frame: NSRect(x: 34, y: 472, width: 76, height: 20), alignment: .right)
        statusTitle.font = titleFont
        view.addSubview(statusTitle)
        let versionText = makeLabel("已集成 7-Zip 25.01（arm64）", frame: NSRect(x: 118, y: 472, width: 400, height: 20))
        versionText.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        view.addSubview(versionText)
        let desc1 = makeLabel("支持创建 7z / ZIP / TAR；可解压 RAR / RAR5 / ISO / CAB 等常见格式。",
                              frame: NSRect(x: 118, y: 448, width: 410, height: 20))
        desc1.font = NSFont.systemFont(ofSize: 11)
        desc1.textColor = .secondaryLabelColor
        view.addSubview(desc1)
        let desc2 = makeLabel("双击压缩包会用内置浏览窗口打开；右键菜单提供压缩与解压功能。",
                              frame: NSRect(x: 118, y: 426, width: 410, height: 20))
        desc2.font = NSFont.systemFont(ofSize: 11)
        desc2.textColor = .secondaryLabelColor
        view.addSubview(desc2)
        let note = makeLabel("注：RAR 为专有格式，开源版仅支持解压，不支持创建。",
                             frame: NSRect(x: 118, y: 402, width: 410, height: 20))
        note.font = NSFont.systemFont(ofSize: 10)
        note.textColor = .tertiaryLabelColor
        view.addSubview(note)

        // 默认压缩参数卡片
        view.addSubview(SettingCardView(frame: NSRect(x: 16, y: 246, width: 528, height: 124)))
        let defaultTitle = makeLabel("默认参数", frame: NSRect(x: 34, y: 342, width: 76, height: 20), alignment: .right)
        defaultTitle.font = titleFont
        view.addSubview(defaultTitle)

        view.addSubview(makeLabel("压缩格式", frame: NSRect(x: 118, y: 342, width: 70, height: 20)))
        let format = NSPopUpButton(frame: NSRect(x: 190, y: 339, width: 150, height: 24), pullsDown: false)
        format.addItems(withTitles: ["7z（推荐）", "ZIP", "TAR"])
        format.selectItem(at: ["7z", "zip", "tar"].firstIndex(of: AppSettings.sevenZipFormat) ?? 0)
        format.action = #selector(changeSevenZipFormat(_:))
        format.target = self
        view.addSubview(format)

        view.addSubview(makeLabel("压缩级别", frame: NSRect(x: 118, y: 306, width: 70, height: 20)))
        let level = NSPopUpButton(frame: NSRect(x: 190, y: 303, width: 150, height: 24), pullsDown: false)
        level.addItems(withTitles: ["0 - 存储", "1 - 最快", "3 - 快速", "5 - 标准", "7 - 最大", "9 - 极限"])
        level.selectItem(at: [0, 1, 3, 5, 7, 9].firstIndex(of: AppSettings.sevenZipLevel) ?? 3)
        level.action = #selector(changeSevenZipLevel(_:))
        level.target = self
        view.addSubview(level)
        let hint = makeLabel("用于「默认参数压缩」与压缩窗口的初始选择；RAR 需使用其他工具创建。",
                             frame: NSRect(x: 34, y: 264, width: 490, height: 20))
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        view.addSubview(hint)

        // 文件关联卡片
        view.addSubview(SettingCardView(frame: NSRect(x: 16, y: 138, width: 528, height: 92)))
        let assocTitle = makeLabel("文件关联", frame: NSRect(x: 34, y: 202, width: 76, height: 20), alignment: .right)
        assocTitle.font = titleFont
        view.addSubview(assocTitle)
        let assocDesc = makeLabel("将 XSpace 设为常见压缩格式的默认打开方式，双击即可浏览。",
                                  frame: NSRect(x: 118, y: 202, width: 400, height: 20))
        assocDesc.font = NSFont.systemFont(ofSize: 11)
        assocDesc.textColor = .secondaryLabelColor
        view.addSubview(assocDesc)
        let setDefault = NSButton(title: "设为默认压缩软件", target: self, action: #selector(setAsDefaultArchiveApp))
        setDefault.frame = NSRect(x: 118, y: 166, width: 160, height: 28)
        setDefault.bezelStyle = .rounded
        view.addSubview(setDefault)

        let item = NSTabViewItem(identifier: "sevenZip")
        item.label = "7-ZIP"
        item.view = view
        return item
    }

    @objc private func changeSevenZipFormat(_ sender: NSPopUpButton) {
        let formats = ["7z", "zip", "tar"]
        AppSettings.sevenZipFormat = formats[min(max(sender.indexOfSelectedItem, 0), formats.count - 1)]
    }

    @objc private func changeSevenZipLevel(_ sender: NSPopUpButton) {
        let levels = [0, 1, 3, 5, 7, 9]
        AppSettings.sevenZipLevel = levels[min(max(sender.indexOfSelectedItem, 0), levels.count - 1)]
    }

    @objc private func setAsDefaultArchiveApp() {
        let appURL = Bundle.main.bundleURL
        let identifiers = [
            "org.7-zip.7-zip-archive", "public.zip-archive", "com.rarlab.rar-archive",
            "public.tar-archive", "org.gnu.gnu-zip-archive", "org.gnu.gnu-zip-tar-archive",
            "public.bzip2-archive", "public.tar-bzip2-archive", "org.tukaani.xz-archive",
            "org.tukaani.tar-xz-archive", "com.microsoft.cab", "public.z-archive",
            "public.cpio-archive"
        ]
        var success = 0
        for id in identifiers {
            guard let type = UTType(id) else { continue }
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
            success += 1
        }
        let alert = NSAlert()
        alert.messageText = success > 0 ? "已设置默认应用" : "设置失败"
        alert.informativeText = success > 0
            ? "已将 XSpace 设为 \(success) 种压缩格式的默认打开方式。"
            : "系统拒绝了设置请求，你也可以在访达中右键压缩包 →「打开方式」手动选择 XSpace。"
        alert.alertStyle = success > 0 ? .informational : .warning
        alert.runModal()
    }

    // MARK: - 快捷键设置（所有可录制快捷键集中在此页）

    private func shortcutsTabItem() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "shortcuts")
        item.label = "快捷键"
        item.view = makeShortcutsView()
        return item
    }

    private func makeShortcutsView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 520))
        let cardX: CGFloat = 16
        let cardW: CGFloat = 528
        let labelX: CGFloat = 34
        let labelW: CGFloat = 76
        let controlX: CGFloat = 116
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

        // 可录制快捷键
        view.addSubview(SettingCardView(frame: NSRect(x: cardX, y: 348, width: cardW, height: 136)))
        let title = makeLabel("快捷键", frame: NSRect(x: labelX, y: 458, width: labelW, height: 20), alignment: .right)
        title.font = titleFont
        view.addSubview(title)
        let hint = makeLabel("点击方框后按下组合键即可更换；按 Esc 取消录制", frame: NSRect(x: controlX, y: 458, width: 400, height: 20))
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        view.addSubview(hint)

        view.addSubview(makeLabel("截图", frame: NSRect(x: labelX, y: 418, width: labelW, height: 20), alignment: .right))
        let screenshotRecorder = ShortcutRecorder(frame: NSRect(x: controlX, y: 414, width: 180, height: 26))
        screenshotRecorder.kind = .screenshot
        view.addSubview(screenshotRecorder)
        self.screenshotRecorder = screenshotRecorder
        let screenshotNote = makeLabel("全局生效，其他 App 前台也能触发", frame: NSRect(x: 310, y: 418, width: 220, height: 20))
        screenshotNote.font = NSFont.systemFont(ofSize: 11)
        screenshotNote.textColor = .tertiaryLabelColor
        view.addSubview(screenshotNote)

        view.addSubview(makeLabel("撤销", frame: NSRect(x: labelX, y: 378, width: labelW, height: 20), alignment: .right))
        let undoRecorder = ShortcutRecorder(frame: NSRect(x: controlX, y: 374, width: 180, height: 26))
        undoRecorder.kind = .undo
        view.addSubview(undoRecorder)
        self.undoRecorder = undoRecorder
        let undoNote = makeLabel("撤销最近一次文件操作，默认 ⌘Z", frame: NSRect(x: 310, y: 378, width: 220, height: 20))
        undoNote.font = NSFont.systemFont(ofSize: 11)
        undoNote.textColor = .tertiaryLabelColor
        view.addSubview(undoNote)

        // 撤销步数
        view.addSubview(SettingCardView(frame: NSRect(x: cardX, y: 226, width: cardW, height: 108)))
        let undoTitle = makeLabel("撤销历史", frame: NSRect(x: labelX, y: 304, width: labelW, height: 20), alignment: .right)
        undoTitle.font = titleFont
        view.addSubview(undoTitle)
        view.addSubview(makeLabel("最多步数", frame: NSRect(x: labelX, y: 270, width: labelW, height: 20), alignment: .right))
        let slider = makeSlider(min: 1, max: 20, value: Double(AppSettings.undoLimit),
                                frame: NSRect(x: controlX, y: 268, width: 260, height: 20),
                                action: #selector(undoLimitChanged(_:)), tag: 0)
        slider.isContinuous = true
        view.addSubview(slider)
        undoLimitSlider = slider
        let value = makeValueLabel(frame: NSRect(x: 392, y: 270, width: 44, height: 20))
        value.stringValue = "\(AppSettings.undoLimit)"
        view.addSubview(value)
        undoLimitLabel = value
        let limitHint = makeLabel("默认 5 步，最多 20 步；修改后立即生效", frame: NSRect(x: controlX, y: 244, width: 400, height: 20))
        limitHint.font = NSFont.systemFont(ofSize: 11)
        limitHint.textColor = .secondaryLabelColor
        view.addSubview(limitHint)

        // 图标缩放修饰键
        view.addSubview(SettingCardView(frame: NSRect(x: cardX, y: 72, width: cardW, height: 138)))
        let zoomTitle = makeLabel("图标缩放", frame: NSRect(x: labelX, y: 180, width: labelW, height: 20), alignment: .right)
        zoomTitle.font = titleFont
        view.addSubview(zoomTitle)
        view.addSubview(makeLabel("滚轮修饰键", frame: NSRect(x: labelX, y: 148, width: labelW, height: 20), alignment: .right))
        let modifier = ModifierRecorder(frame: NSRect(x: controlX, y: 144, width: 180, height: 26))
        view.addSubview(modifier)
        modifierRecorder = modifier
        let modifierHint = makeLabel("点击方框后按下 ⌃ / ⌥ / ⇧ / ⌘ 即可更换；在窗格内按住它滚动滚轮可缩放图标",
                                     frame: NSRect(x: controlX, y: 120, width: 400, height: 20))
        modifierHint.font = NSFont.systemFont(ofSize: 11)
        modifierHint.textColor = .secondaryLabelColor
        view.addSubview(modifierHint)

        let reset = NSButton(title: "恢复默认快捷键", target: self, action: #selector(resetShortcutDefaults))
        reset.frame = NSRect(x: controlX, y: 84, width: 130, height: 26)
        reset.bezelStyle = .rounded
        view.addSubview(reset)
        return view
    }

    @objc private func undoLimitChanged(_ sender: NSSlider) {
        AppSettings.undoLimit = Int(sender.intValue)
        undoLimitLabel?.stringValue = "\(AppSettings.undoLimit)"
    }

    @objc private func resetShortcutDefaults() {
        AppSettings.screenshotShortcut = .defaultScreenshot
        AppSettings.undoShortcut = .defaultUndo
        AppSettings.iconResizeModifier = .control
        AppSettings.undoLimit = 5
        screenshotRecorder?.refresh()
        undoRecorder?.refresh()
        modifierRecorder?.refresh()
        undoLimitSlider?.intValue = 5
        undoLimitLabel?.stringValue = "5"
    }

    // MARK: - 布局设置

    private func layoutTabItem() -> NSTabViewItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 520))
        layoutRadios.removeAll()

        let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

        view.addSubview(SettingCardView(frame: NSRect(x: 16, y: 220, width: 528, height: 272)))
        let title = makeLabel("窗口布局", frame: NSRect(x: 34, y: 466, width: 76, height: 20), alignment: .right)
        title.font = titleFont
        view.addSubview(title)
        let hint = makeLabel("选择主窗口的窗格数量与排列方式，切换后立即应用",
                             frame: NSRect(x: 116, y: 466, width: 400, height: 20))
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        view.addSubview(hint)

        for (index, layout) in PaneLayout.allCases.enumerated() {
            let y = 420 - CGFloat(index) * 36
            let radio = NSButton(radioButtonWithTitle: layout.title,
                                 target: self, action: #selector(layoutRadioChanged(_:)))
            radio.frame = NSRect(x: 116, y: y, width: 340, height: 24)
            radio.tag = index
            radio.state = AppSettings.paneLayout == layout ? .on : .off
            view.addSubview(radio)
            layoutRadios.append(radio)
        }

        view.addSubview(SettingCardView(frame: NSRect(x: 16, y: 100, width: 528, height: 104)))
        let newWindowTitle = makeLabel("新窗口", frame: NSRect(x: 34, y: 172, width: 76, height: 20), alignment: .right)
        newWindowTitle.font = titleFont
        view.addSubview(newWindowTitle)
        let newWindowHint = makeLabel("在文件夹上右键选择「新窗口打开」，会以单窗口形式弹出独立窗口，关闭它不影响主程序。",
                                      frame: NSRect(x: 116, y: 122, width: 400, height: 36))
        newWindowHint.font = NSFont.systemFont(ofSize: 11)
        newWindowHint.textColor = .secondaryLabelColor
        newWindowHint.lineBreakMode = .byWordWrapping
        newWindowHint.maximumNumberOfLines = 2
        view.addSubview(newWindowHint)

        let item = NSTabViewItem(identifier: "layout")
        item.label = "布局"
        item.view = view
        return item
    }

    @objc private func layoutRadioChanged(_ sender: NSButton) {
        let layout = PaneLayout.at(sender.tag)
        AppSettings.paneLayout = layout
        for radio in layoutRadios {
            radio.state = (radio === sender) ? .on : .off
        }
        NotificationCenter.default.post(name: .xspaceLayoutChanged, object: nil)
        rebuildPaneDependentTabs()
    }

    /// 布局切换后重建「外观」「壁纸」页，让窗格行数跟随当前布局
    private func rebuildPaneDependentTabs() {
        guard let tabs = preferencesTabs else { return }
        for item in tabs.tabViewItems {
            switch item.identifier as? String {
            case "appearance": item.view = makeAppearanceView()
            case "wallpaper": item.view = makeWallpaperView()
            default: break
            }
        }
        if let selected = tabs.selectedTabViewItem {
            tabs.selectTabViewItem(selected)
        }
        updatePreferenceLabels()
    }

    private func generalTabItem() -> NSTabViewItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 520))
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

        // 文件操作
        view.addSubview(SettingCardView(frame: NSRect(x: 16, y: 356, width: 528, height: 142)))
        let fileTitle = makeLabel("文件操作", frame: NSRect(x: 34, y: 470, width: 76, height: 20), alignment: .right)
        fileTitle.font = titleFont
        view.addSubview(fileTitle)
        let hidden = NSButton(checkboxWithTitle: "显示隐藏文件", target: self, action: #selector(toggleHiddenCheckbox(_:)))
        hidden.frame = NSRect(x: 116, y: 444, width: 280, height: 22)
        hidden.state = AppSettings.showHiddenFiles ? .on : .off
        let confirm = NSButton(checkboxWithTitle: "移到废纸篓前确认", target: self, action: #selector(toggleConfirmCheckbox(_:)))
        confirm.frame = NSRect(x: 116, y: 418, width: 280, height: 22)
        confirm.state = AppSettings.confirmBeforeTrash ? .on : .off
        let confirmDelete = NSButton(checkboxWithTitle: "直接删除前确认", target: self, action: #selector(toggleConfirmDeleteCheckbox(_:)))
        confirmDelete.frame = NSRect(x: 116, y: 392, width: 280, height: 22)
        confirmDelete.state = AppSettings.confirmBeforeDelete ? .on : .off
        let sidebar = NSButton(checkboxWithTitle: "启动时显示侧边栏", target: self, action: #selector(toggleSidebarCheckbox(_:)))
        sidebar.frame = NSRect(x: 116, y: 366, width: 280, height: 22)
        sidebar.state = AppSettings.sidebarVisible ? .on : .off
        [hidden, confirm, confirmDelete, sidebar].forEach { view.addSubview($0) }

        // 截图（快捷键在「快捷键」页）
        view.addSubview(SettingCardView(frame: NSRect(x: 16, y: 270, width: 528, height: 76)))
        let screenshotTitle = makeLabel("截图", frame: NSRect(x: 34, y: 318, width: 76, height: 20), alignment: .right)
        screenshotTitle.font = titleFont
        view.addSubview(screenshotTitle)
        view.addSubview(makeLabel("保存目录", frame: NSRect(x: 34, y: 286, width: 76, height: 20), alignment: .right))
        let chooseDirectory = NSButton(title: "选择…", target: self, action: #selector(chooseScreenshotDirectory))
        chooseDirectory.frame = NSRect(x: 116, y: 283, width: 80, height: 26)
        chooseDirectory.bezelStyle = .rounded
        view.addSubview(chooseDirectory)
        let defaultDirectory = NSButton(title: "默认", target: self, action: #selector(resetScreenshotDirectory))
        defaultDirectory.frame = NSRect(x: 204, y: 283, width: 64, height: 26)
        defaultDirectory.bezelStyle = .rounded
        view.addSubview(defaultDirectory)

        let directoryLabel = makeLabel(AppSettings.screenshotDirectory.path,
                                       frame: NSRect(x: 284, y: 286, width: 246, height: 20),
                                       alignment: .right)
        directoryLabel.font = NSFont.systemFont(ofSize: 11)
        directoryLabel.textColor = .secondaryLabelColor
        directoryLabel.lineBreakMode = .byTruncatingMiddle
        directoryLabel.toolTip = AppSettings.screenshotDirectory.path
        view.addSubview(directoryLabel)
        screenshotDirectoryLabel = directoryLabel

        // 快速访问
        view.addSubview(SettingCardView(frame: NSRect(x: 16, y: 28, width: 528, height: 228)))
        let quickTitle = makeLabel("快速访问", frame: NSRect(x: 34, y: 228, width: 100, height: 20))
        quickTitle.font = titleFont
        view.addSubview(quickTitle)
        let quickHint = makeLabel("选中后可用「上移 / 下移」调整侧边栏顺序", frame: NSRect(x: 180, y: 228, width: 348, height: 20),
                                  alignment: .right)
        quickHint.font = NSFont.systemFont(ofSize: 11)
        quickHint.textColor = .tertiaryLabelColor
        view.addSubview(quickHint)

        let quickView = QuickAccessSettingsView(frame: NSRect(x: 32, y: 76, width: 496, height: 140))
        view.addSubview(quickView)

        let reset = NSButton(title: "恢复默认目录", target: self, action: #selector(resetFromPreferences))
        reset.frame = NSRect(x: 32, y: 38, width: 160, height: 28)
        reset.bezelStyle = .rounded
        view.addSubview(reset)

        let version = makeLabel("XSpace \(Self.appVersion)", frame: NSRect(x: 368, y: 42, width: 160, height: 16),
                                alignment: .right)
        version.font = NSFont.systemFont(ofSize: 10)
        version.textColor = .tertiaryLabelColor
        view.addSubview(version)

        let item = NSTabViewItem(identifier: "general")
        item.label = "常规"
        item.view = view
        return item
    }

    private func makeSeparator(y: CGFloat) -> NSBox {
        let box = NSBox(frame: NSRect(x: 32, y: y, width: 496, height: 1))
        box.boxType = .separator
        return box
    }

    private func appearanceTabItem() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "appearance")
        item.label = "外观"
        item.view = makeAppearanceView()
        return item
    }

    /// 「外观」页内容按当前布局的窗格数量生成，切换布局后会重建
    private func makeAppearanceView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 520))

        iconSliders.removeAll()
        textSliders.removeAll()
        iconValueLabels.removeAll()
        textValueLabels.removeAll()

        let paneCount = AppSettings.paneLayout.paneCount
        let compact = paneCount >= PaneLayout.maxPanes
        let topY: CGFloat = 456
        let stride: CGFloat = compact ? 82 : 108
        let innerGap: CGFloat = compact ? 34 : 40

        view.addSubview(SettingCardView(frame: NSRect(x: 16, y: 140, width: 528, height: 360)))
        let title = makeLabel("窗格细项", frame: NSRect(x: 34, y: 476, width: 110, height: 20), alignment: .right)
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        view.addSubview(title)
        let countHint = makeLabel("当前布局共 \(paneCount) 个窗格，下面的细项按窗格顺序一一对应",
                                  frame: NSRect(x: 152, y: 476, width: 376, height: 16))
        countHint.font = NSFont.systemFont(ofSize: 11)
        countHint.textColor = .secondaryLabelColor
        view.addSubview(countHint)

        for index in 0..<paneCount {
            let top = topY - CGFloat(index) * stride

            view.addSubview(makeLabel("窗格 \(index + 1) 图标大小",
                                      frame: NSRect(x: 34, y: top, width: 110, height: 20), alignment: .right))
            let iconSlider = makeSlider(min: 40, max: 256, value: Double(AppSettings.iconSize(for: index)),
                                        frame: NSRect(x: 152, y: top - 2, width: 240, height: 20),
                                        action: #selector(iconSizeChanged(_:)), tag: index)
            let iconValue = makeValueLabel(frame: NSRect(x: 420, y: top, width: 56, height: 20))
            view.addSubview(iconSlider)
            view.addSubview(iconValue)
            iconSliders.append(iconSlider)
            iconValueLabels.append(iconValue)

            view.addSubview(makeLabel("窗格 \(index + 1) 文字大小",
                                      frame: NSRect(x: 34, y: top - innerGap, width: 110, height: 20), alignment: .right))
            let textSlider = makeSlider(min: 10, max: 20, value: Double(AppSettings.textSize(for: index)),
                                        frame: NSRect(x: 152, y: top - innerGap - 2, width: 240, height: 20),
                                        action: #selector(textSizeChanged(_:)), tag: index)
            let textValue = makeValueLabel(frame: NSRect(x: 420, y: top - innerGap, width: 56, height: 20))
            view.addSubview(textSlider)
            view.addSubview(textValue)
            textSliders.append(textSlider)
            textValueLabels.append(textValue)
        }

        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetAppearanceDefaults))
        reset.frame = NSRect(x: 32, y: 96, width: 100, height: 28)
        reset.bezelStyle = .rounded
        view.addSubview(reset)
        let resetHint = makeLabel("仅重置各窗格的图标与文字大小；滚轮缩放修饰键请到「快捷键」页设置",
                                  frame: NSRect(x: 146, y: 100, width: 390, height: 20))
        resetHint.font = NSFont.systemFont(ofSize: 11)
        resetHint.textColor = .tertiaryLabelColor
        view.addSubview(resetHint)

        refreshAppearanceValues()
        return view
    }

    /// 滑块右侧的数值（等宽数字，右对齐）
    private func makeValueLabel(frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.frame = frame
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.isEditable = false
        label.isSelectable = false
        return label
    }

    /// 从设置读回各窗格的图标 / 文字大小，刷新滑块与数值
    private func refreshAppearanceValues() {
        let count = max(iconSliders.count, textSliders.count)
        for index in 0..<count {
            guard index < iconSliders.count, index < textSliders.count,
                  index < iconValueLabels.count, index < textValueLabels.count else { continue }
            let icon = AppSettings.iconSize(for: index)
            let text = AppSettings.textSize(for: index)
            iconSliders[index].doubleValue = Double(icon)
            textSliders[index].doubleValue = Double(text)
            iconValueLabels[index].stringValue = "\(Int(icon))"
            textValueLabels[index].stringValue = "\(Int(text))"
        }
    }

    @objc private func resetAppearanceDefaults() {
        // 一次重置所有可能用到的窗格，避免切换布局后又出现旧值
        for index in 0..<PaneLayout.maxPanes {
            AppSettings.setIconSize(64, for: index)
            AppSettings.setTextSize(12, for: index)
        }
        refreshAppearanceValues()
        notifyAppearanceChanged()
    }

    private func wallpaperTabItem() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "wallpaper")
        item.label = "壁纸"
        item.view = makeWallpaperView()
        return item
    }

    /// 「壁纸」页内容按当前布局的窗格数量生成，切换布局后会重建
    private func makeWallpaperView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 520))

        let paneCount = AppSettings.paneLayout.paneCount
        let compact = paneCount >= PaneLayout.maxPanes

        // 统一栅格：标签右对齐到同一列，所有控件从同一列起始
        let cardX: CGFloat = 16
        let cardW: CGFloat = 528
        let labelX: CGFloat = 34
        let labelW: CGFloat = 74
        let controlX: CGFloat = 116
        let cardRight = cardX + cardW             // 544
        let stateW = cardRight - 20 - (controlX + 104 + 8 + 64 + 10)   // 状态文字可用宽度
        let stateX = cardRight - 20 - stateW
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

        // MARK: 全局壁纸
        view.addSubview(SettingCardView(frame: NSRect(x: cardX, y: 344, width: cardW, height: 136)))

        let globalTitle = makeLabel("全局壁纸", frame: NSRect(x: labelX, y: 450, width: labelW, height: 20),
                                    alignment: .right)
        globalTitle.font = titleFont
        view.addSubview(globalTitle)
        view.addSubview(makeButton("选择图片…", frame: NSRect(x: controlX, y: 447, width: 104, height: 26),
                                   action: #selector(chooseWallpaper(_:)), tag: -1))
        view.addSubview(makeButton("清除", frame: NSRect(x: controlX + 112, y: 447, width: 64, height: 26),
                                   action: #selector(clearWallpaper(_:)), tag: -1))
        let globalPath = makeLabel("", frame: NSRect(x: stateX, y: 450, width: stateW, height: 20),
                                   tag: 300, alignment: .right)
        globalPath.font = NSFont.systemFont(ofSize: 11)
        globalPath.textColor = .secondaryLabelColor
        view.addSubview(globalPath)

        view.addSubview(makeLabel("高斯模糊", frame: NSRect(x: labelX, y: 410, width: labelW, height: 20),
                                  alignment: .right))
        view.addSubview(makeSlider(min: 1, max: 100, value: Double(AppSettings.globalWallpaperBlur),
                                   frame: NSRect(x: controlX, y: 412, width: 196, height: 20),
                                   action: #selector(globalBlurChanged(_:)), tag: -1))
        view.addSubview(makeLabel("", frame: NSRect(x: controlX + 202, y: 410, width: 40, height: 20), tag: 400))

        view.addSubview(makeLabel("填充方式", frame: NSRect(x: labelX, y: 376, width: labelW, height: 20),
                                  alignment: .right))
        view.addSubview(makePopup(frame: NSRect(x: controlX, y: 370, width: 110, height: 26),
                                  selected: AppSettings.globalWallpaperMode.index,
                                  action: #selector(globalWallpaperModeChanged(_:)), tag: 1000))

        // MARK: 窗格独立壁纸
        // 四窗格时压缩行距；窗格较少时卡片贴合内容，避免大片空白
        let paneCardTop: CGFloat = 332
        let firstRowY: CGFloat = compact ? 272 : 276
        let rowStride: CGFloat = compact ? 68 : 84
        let rowGap: CGFloat = compact ? 32 : 34
        let lastRowY = firstRowY - CGFloat(paneCount - 1) * rowStride - rowGap
        let paneCardBottom: CGFloat
        if paneCount >= 3 {
            paneCardBottom = compact ? 12 : 48
        } else {
            paneCardBottom = max(8, lastRowY - 26)
        }

        view.addSubview(SettingCardView(frame: NSRect(x: cardX, y: paneCardBottom,
                                                     width: cardW, height: paneCardTop - paneCardBottom)))

        let paneTitle = makeLabel("窗格壁纸", frame: NSRect(x: labelX, y: 300, width: labelW, height: 20),
                                  alignment: .right)
        paneTitle.font = titleFont
        view.addSubview(paneTitle)
        let paneHint = makeLabel("当前布局共 \(paneCount) 个窗格 · 未设置时使用全局壁纸",
                                 frame: NSRect(x: controlX, y: 300, width: cardRight - 20 - controlX, height: 20),
                                 alignment: .right)
        paneHint.font = NSFont.systemFont(ofSize: 11)
        paneHint.textColor = .tertiaryLabelColor
        view.addSubview(paneHint)

        for index in 0..<paneCount {
            let rowA = firstRowY - CGFloat(index) * rowStride        // 第一行中线
            let rowB = rowA - rowGap                                 // 第二行中线

            view.addSubview(makeLabel("窗格 \(index + 1)", frame: NSRect(x: labelX, y: rowA - 10, width: labelW, height: 20),
                                      alignment: .right))
            view.addSubview(makeButton("选择图片…", frame: NSRect(x: controlX, y: rowA - 13, width: 104, height: 26),
                                       action: #selector(chooseWallpaper(_:)), tag: index))
            view.addSubview(makeButton("清除", frame: NSRect(x: controlX + 112, y: rowA - 13, width: 64, height: 26),
                                       action: #selector(clearWallpaper(_:)), tag: index))
            let pathLabel = makeLabel("", frame: NSRect(x: stateX, y: rowA - 10, width: stateW, height: 20),
                                      tag: 500 + index, alignment: .right)
            pathLabel.font = NSFont.systemFont(ofSize: 11)
            pathLabel.textColor = .secondaryLabelColor
            view.addSubview(pathLabel)

            view.addSubview(makeLabel("模糊", frame: NSRect(x: labelX, y: rowB - 10, width: labelW, height: 20),
                                      alignment: .right))
            view.addSubview(makeSlider(min: 1, max: 100, value: Double(AppSettings.paneWallpaperBlur(for: index)),
                                       frame: NSRect(x: controlX, y: rowB - 8, width: 196, height: 20),
                                       action: #selector(paneBlurChanged(_:)), tag: index))
            view.addSubview(makeLabel("", frame: NSRect(x: controlX + 202, y: rowB - 10, width: 40, height: 20),
                                      tag: 600 + index))

            view.addSubview(makeLabel("填充", frame: NSRect(x: controlX + 252, y: rowB - 10, width: 40, height: 20),
                                      alignment: .right))
            view.addSubview(makePopup(frame: NSRect(x: controlX + 300, y: rowB - 13, width: 110, height: 26),
                                      selected: AppSettings.paneWallpaperMode(for: index).index,
                                      action: #selector(paneWallpaperModeChanged(_:)), tag: 1100 + index))
        }

        return view
    }

    private func makeLabel(_ title: String, frame: NSRect, tag: Int = 0,
                           alignment: NSTextAlignment = .left) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.frame = frame
        label.tag = tag
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    private func makeSlider(min: Double, max: Double, value: Double, frame: NSRect, action: Selector, tag: Int) -> NSSlider {
        let slider = NSSlider(frame: frame)
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = value
        slider.target = self
        slider.action = action
        slider.tag = tag
        return slider
    }

    private func makeButton(_ title: String, frame: NSRect, action: Selector, tag: Int) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = frame
        button.bezelStyle = .rounded
        button.tag = tag
        return button
    }

    private func makePopup(frame: NSRect, selected: Int, action: Selector, tag: Int) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: frame, pullsDown: false)
        popup.addItems(withTitles: WallpaperFillMode.allCases.map(\.title))
        popup.selectItem(at: min(max(0, selected), WallpaperFillMode.allCases.count - 1))
        popup.target = self
        popup.action = action
        popup.tag = tag
        return popup
    }

    private func notifyAppearanceChanged() {
        NotificationCenter.default.post(name: .xspaceAppearanceChanged, object: nil)
    }

    /// 壁纸在设置里的显示名：内置图给出中文名，其它显示文件名
    private func wallpaperDisplayName(_ path: String?) -> String {
        guard let path else { return "未设置" }
        if path == AppSettings.bundledWallpaperPath { return "内置星空（默认）" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func updatePreferenceLabels() {
        guard let content = preferencesWindow?.contentView else { return }
        // 窗格数量随布局变化，按最大数量刷新；不存在的控件自然被忽略
        for index in 0..<PaneLayout.maxPanes {
            (content.viewWithTag(500 + index) as? NSTextField)?.stringValue = wallpaperDisplayName(AppSettings.paneWallpaperPath(for: index))
            (content.viewWithTag(600 + index) as? NSTextField)?.stringValue = "\(AppSettings.paneWallpaperBlur(for: index))"
        }
        (content.viewWithTag(300) as? NSTextField)?.stringValue = wallpaperDisplayName(AppSettings.globalWallpaperPath)
        (content.viewWithTag(400) as? NSTextField)?.stringValue = "\(AppSettings.globalWallpaperBlur)"
    }

    @objc private func iconSizeChanged(_ sender: NSSlider) {
        AppSettings.setIconSize(CGFloat(sender.doubleValue), for: sender.tag)
        if sender.tag < iconValueLabels.count {
            iconValueLabels[sender.tag].stringValue = "\(Int(sender.doubleValue))"
        }
        notifyAppearanceChanged()
    }

    @objc private func textSizeChanged(_ sender: NSSlider) {
        AppSettings.setTextSize(CGFloat(sender.doubleValue), for: sender.tag)
        if sender.tag < textValueLabels.count {
            textValueLabels[sender.tag].stringValue = "\(Int(sender.doubleValue))"
        }
        notifyAppearanceChanged()
    }

    @objc private func globalBlurChanged(_ sender: NSSlider) {
        AppSettings.globalWallpaperBlur = Int(sender.integerValue)
        updatePreferenceLabels()
        notifyAppearanceChanged()
    }

    @objc private func paneBlurChanged(_ sender: NSSlider) {
        AppSettings.setPaneWallpaperBlur(Int(sender.integerValue), for: sender.tag)
        updatePreferenceLabels()
        notifyAppearanceChanged()
    }

    @objc private func globalWallpaperModeChanged(_ sender: NSPopUpButton) {
        AppSettings.globalWallpaperMode = WallpaperFillMode.mode(at: sender.indexOfSelectedItem)
        notifyAppearanceChanged()
    }

    @objc private func paneWallpaperModeChanged(_ sender: NSPopUpButton) {
        AppSettings.setPaneWallpaperMode(WallpaperFillMode.mode(at: sender.indexOfSelectedItem), for: sender.tag - 1100)
        notifyAppearanceChanged()
    }

    @objc private func chooseWallpaper(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "选择壁纸图片"
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.image]
        } else {
            panel.allowedFileTypes = ["jpg", "jpeg", "png", "gif", "tiff", "heic"]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if sender.tag < 0 {
            AppSettings.globalWallpaperPath = url.path
        } else {
            AppSettings.setPaneWallpaperPath(url.path, for: sender.tag)
        }
        updatePreferenceLabels()
        notifyAppearanceChanged()
    }

    @objc private func clearWallpaper(_ sender: NSButton) {
        if sender.tag < 0 {
            AppSettings.globalWallpaperPath = nil
        } else {
            AppSettings.setPaneWallpaperPath(nil, for: sender.tag)
        }
        updatePreferenceLabels()
        notifyAppearanceChanged()
    }

    @objc private func toggleHiddenCheckbox(_ sender: NSButton) {
        AppSettings.showHiddenFiles = sender.state == .on
        for controller in controllers.values { controller.refresh() }
    }

    @objc private func toggleConfirmCheckbox(_ sender: NSButton) {
        AppSettings.confirmBeforeTrash = sender.state == .on
    }

    @objc private func toggleConfirmDeleteCheckbox(_ sender: NSButton) {
        AppSettings.confirmBeforeDelete = sender.state == .on
    }

    @objc private func toggleSidebarCheckbox(_ sender: NSButton) {
        AppSettings.sidebarVisible = sender.state == .on
    }

    @objc private func chooseScreenshotDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择截图保存目录"
        panel.message = "截图会保存到这里"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppSettings.screenshotDirectory
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            AppSettings.screenshotDirectory = url
            self?.refreshScreenshotDirectoryLabel()
        }
        if let preferencesWindow {
            panel.beginSheetModal(for: preferencesWindow, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    @objc private func resetScreenshotDirectory() {
        AppSettings.screenshotDirectory = AppSettings.defaultScreenshotDirectory
        refreshScreenshotDirectoryLabel()
    }

    private func refreshScreenshotDirectoryLabel() {
        let path = AppSettings.screenshotDirectory.path
        screenshotDirectoryLabel?.stringValue = path
        screenshotDirectoryLabel?.toolTip = path
    }

    @objc private func resetFromPreferences() {
        for controller in controllers.values { controller.resetPanes() }
    }
}

// 显式启动 AppKit 主循环，避免依赖 @main 合成入口
let appDelegate = AppDelegate()
let application = NSApplication.shared
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
