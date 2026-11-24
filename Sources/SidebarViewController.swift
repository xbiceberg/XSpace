import Foundation
import AppKit

protocol SidebarDelegate: AnyObject {
    func sidebar(_ sidebar: SidebarViewController, didSelect url: URL)
    func sidebarCurrentURL(_ sidebar: SidebarViewController) -> URL
    func sidebarDidRequestAddBookmark(_ sidebar: SidebarViewController)
    func sidebarDidDropFiles(_ sidebar: SidebarViewController)
}

private enum SidebarAction {
    case addBookmark
}

private final class SidebarCellView: NSTableCellView {
    let ejectButton = NSButton(frame: NSRect(x: 0, y: 0, width: 18, height: 16))
    var onEject: (() -> Void)?
    var isHeaderRow = false
    var showsEject = false {
        didSet { ejectButton.isHidden = !showsEject; needsLayout = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let icon = NSImageView(frame: NSRect(x: 14, y: 3, width: 17, height: 17))
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)
        imageView = icon
        let text = NSTextField(labelWithString: "")
        text.frame = NSRect(x: 34, y: 3, width: 150, height: 18)
        text.lineBreakMode = .byTruncatingMiddle
        text.isEditable = false
        text.isSelectable = false
        addSubview(text)
        textField = text
        ejectButton.bezelStyle = .regularSquare
        ejectButton.isBordered = false
        ejectButton.image = Symbol.image("eject", fallback: "NSActionTemplate")
        ejectButton.imagePosition = .imageOnly
        ejectButton.contentTintColor = .secondaryLabelColor
        ejectButton.toolTip = "推出"
        ejectButton.target = self
        ejectButton.action = #selector(ejectTapped)
        ejectButton.isHidden = true
        addSubview(ejectButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(image: NSImage?, title: String, header: Bool, eject: Bool) {
        isHeaderRow = header
        imageView?.image = image
        textField?.stringValue = title
        showsEject = eject
        needsLayout = true
    }

    @objc private func ejectTapped() { onEject?() }

    override func layout() {
        super.layout()
        let width = bounds.width
        let iconX: CGFloat = isHeaderRow ? 8 : 14
        let textX: CGFloat = isHeaderRow ? 28 : 34
        imageView?.frame = NSRect(x: iconX, y: 3, width: 17, height: 17)
        let rightInset: CGFloat = showsEject ? 28 : 8
        textField?.frame = NSRect(x: textX, y: 3, width: max(40, width - textX - rightInset), height: 18)
        textField?.font = isHeaderRow
            ? NSFont.systemFont(ofSize: 11, weight: .semibold)
            : NSFont.systemFont(ofSize: 12)
        textField?.textColor = isHeaderRow ? .secondaryLabelColor : .labelColor
        ejectButton.frame = NSRect(x: max(0, width - 24), y: 4, width: 18, height: 16)
    }
}

final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: SidebarDelegate?

    private struct Entry {
        let title: String
        let url: URL?
        let icon: NSImage?
        let isHeader: Bool
        let isAction: Bool
        let action: SidebarAction?
        let isQuickAccess: Bool
        let isBookmark: Bool
        let canEject: Bool

        static func header(_ title: String) -> Entry {
            Entry(title: title, url: nil, icon: nil, isHeader: true, isAction: false,
                  action: nil, isQuickAccess: false, isBookmark: false, canEject: false)
        }
        static func item(_ title: String, _ url: URL, _ icon: NSImage?,
                         quickAccess: Bool = false, bookmark: Bool = false, ejectable: Bool = false) -> Entry {
            Entry(title: title, url: url, icon: icon, isHeader: false, isAction: false,
                  action: nil, isQuickAccess: quickAccess, isBookmark: bookmark, canEject: ejectable)
        }
        static func action(_ title: String, _ icon: NSImage?, _ action: SidebarAction) -> Entry {
            Entry(title: title, url: nil, icon: icon, isHeader: false, isAction: true,
                  action: action, isQuickAccess: false, isBookmark: false, canEject: false)
        }
    }

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "XSpace")
    private var entries: [Entry] = []

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    /// 整窗壁纸生效时侧边栏改为半透明，让同一张壁纸连续透出
    func setWorkspaceWallpaperActive(_ active: Bool) {
        let color = active
            ? NSColor.windowBackgroundColor.withAlphaComponent(0.55)
            : NSColor.windowBackgroundColor
        view.layer?.backgroundColor = color.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.frame = NSRect(x: 14, y: 0, width: 200, height: 34)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.alignment = .left
        view.addSubview(titleLabel)

        scrollView.frame = NSRect(x: 0, y: 0, width: 200, height: 500)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        view.addSubview(scrollView)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        column.width = 198
        tableView.addTableColumn(column)
        tableView.style = .sourceList
        tableView.rowHeight = 24
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(clickRow)
        // 文件列表里的项目可以直接拖到「快速访问」「位置」下的目录项
        tableView.registerForDraggedTypes([.fileURL])
        scrollView.documentView = tableView

        // 安装第三方软件时挂载的 DMG / 外接卷出现或消失后自动刷新侧边栏
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(self, selector: #selector(volumesChanged),
                                    name: NSWorkspace.didMountNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(volumesChanged),
                                    name: NSWorkspace.didUnmountNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(customPathsChanged),
                                               name: .xspaceCustomPathsChanged, object: nil)
        rebuild()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func volumesChanged() {
        DispatchQueue.main.async { [weak self] in self?.rebuild() }
    }

    @objc private func customPathsChanged() {
        DispatchQueue.main.async { [weak self] in self?.rebuild() }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let height = view.bounds.height
        titleLabel.frame = NSRect(x: 14, y: height - 34, width: max(1, view.bounds.width - 20), height: 30)
        scrollView.frame = NSRect(x: 0, y: 0, width: view.bounds.width, height: max(0, height - 40))
        tableView.frame = NSRect(x: 0, y: 0, width: view.bounds.width, height: max(0, height - 40))
    }

    func rebuild() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var list: [Entry] = []
        list.append(.header("快速访问"))
        // 顺序、内容都来自偏好设置；目录已被删除的条目自动跳过
        for item in AppSettings.quickAccessItems {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            list.append(.item(item.title.isEmpty ? item.url.lastPathComponent : item.title,
                              item.url, Symbol.image(item.icon, fallback: "folder"), quickAccess: true))
        }

        list.append(.header("位置"))
        for volume in fm.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [] {
            let name = volume.lastPathComponent.isEmpty ? "磁盘" : volume.lastPathComponent
            let ejectable = isEjectable(volume)
            list.append(.item(name, volume, Symbol.image(ejectable ? "externaldrive" : "internaldrive"),
                              ejectable: ejectable))
        }
        list.append(.item("废纸篓", home.appendingPathComponent(".Trash"), Symbol.image("trash")))
        entries = list
        tableView.reloadData()
    }

    /// 内置启动盘不显示推出；其它挂载卷（安装第三方软件的 DMG、外接磁盘等）显示推出按钮
    private func isEjectable(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path == "/" || path.hasPrefix("/System/Volumes/") { return false }
        if path.hasPrefix("/Volumes/") { return true }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        if let values = try? url.resourceValues(forKeys: [.volumeIsEjectableKey, .volumeIsRemovableKey]) {
            return (values.volumeIsEjectable ?? false) || (values.volumeIsRemovable ?? false)
        }
        return false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < entries.count else { return nil }
        let entry = entries[row]
        let identifier = NSUserInterfaceItemIdentifier(entry.isHeader ? "header" : "entry")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? SidebarCellView) ?? {
            let cell = SidebarCellView(frame: NSRect(x: 0, y: 0, width: 190, height: 24))
            cell.identifier = identifier
            return cell
        }()
        cell.configure(image: entry.icon, title: entry.title, header: entry.isHeader, eject: entry.canEject)
        cell.onEject = { [weak self] in
            guard let self else { return }
            let row = self.tableView.row(for: cell)
            guard row >= 0 else { return }
            self.ejectVolume(at: row)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        row < entries.count && !entries[row].isHeader
    }

    // MARK: - 拖放到侧边栏目录

    private func entry(at row: Int) -> Entry? {
        guard row >= 0, row < entries.count else { return nil }
        let entry = entries[row]
        return entry.isHeader || entry.isAction ? nil : entry
    }

    private func isTrashRow(_ entry: Entry) -> Bool {
        guard let url = entry.url else { return false }
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        return url.standardizedFileURL.path == trash.standardizedFileURL.path
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard let entry = entry(at: row), let url = entry.url else { return [] }
        if isTrashRow(entry) { return .move }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return [] }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let entry = entry(at: row), let url = entry.url else { return false }
        let pasteboard = info.draggingPasteboard
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }

        if isTrashRow(entry) {
            FileOperations.trashItems(urls)
        } else {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            // 已经在目标目录里的文件不再搬一次，避免出现「xxx (2)」副本
            let moving = !NSEvent.modifierFlags.contains(.option)
            let incoming = moving ? urls.filter {
                $0.deletingLastPathComponent().standardizedFileURL.path != url.standardizedFileURL.path
            } : urls
            guard !incoming.isEmpty else { return true }
            _ = FileOperations.copyItems(incoming, into: url, move: moving)
        }
        delegate?.sidebarDidDropFiles(self)
        return true
    }

    func tableView(_ tableView: NSTableView, menuFor tableColumn: NSTableColumn?, row: Int) -> NSMenu? {
        guard row >= 0, row < entries.count, !entries[row].isHeader else { return nil }
        let entry = entries[row]
        let menu = NSMenu()

        func add(_ title: String, _ action: Selector, object: Any? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = object
            menu.addItem(item)
        }

        if entry.canEject, let url = entry.url {
            add("推出", #selector(ejectMenuItem(_:)), object: url)
            menu.addItem(.separator())
        }
        if entry.isQuickAccess, let url = entry.url {
            add("从快速访问移除", #selector(removeCustomPathItem(_:)), object: url)
        }
        return menu.items.isEmpty ? nil : menu
    }

    @objc private func clickRow() {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return }
        let entry = entries[row]
        if entry.isAction {
            if entry.action == .addBookmark { delegate?.sidebarDidRequestAddBookmark(self) }
        } else if let url = entry.url {
            delegate?.sidebar(self, didSelect: url)
        }
    }

    // MARK: - 推出挂载卷（例如安装第三方软件时挂载的 DMG）

    private func ejectVolume(at row: Int) {
        guard row >= 0, row < entries.count, entries[row].canEject, let url = entries[row].url else { return }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        } catch {
            Dialog.alert(title: "推出失败", message: "无法推出“\(url.lastPathComponent)”：\(error.localizedDescription)", window: view.window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.rebuild() }
    }

    @objc private func ejectMenuItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let row = entries.firstIndex(where: { $0.url?.standardizedFileURL == url.standardizedFileURL && $0.canEject }) else { return }
        ejectVolume(at: row)
    }

    // MARK: - 自定义路径与书签

    @objc func addBookmark() {
        delegate?.sidebarDidRequestAddBookmark(self)
    }

    @objc private func removeCustomPathItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        AppSettings.removeQuickAccess(path: url.path)
        rebuild()
    }

    @objc private func removeBookmarkItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        AppSettings.bookmarks = AppSettings.bookmarks.filter { $0.standardizedFileURL != url.standardizedFileURL }
        rebuild()
    }
}
