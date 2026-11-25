import Foundation
import AppKit
import UniformTypeIdentifiers

protocol PaneDelegate: AnyObject {
    func paneDidBecomeActive(_ pane: PaneViewController)
    func paneDidChangeState(_ pane: PaneViewController)
    func pane(_ pane: PaneViewController, openInOtherPane url: URL)
    /// 用独立的单窗口打开某个目录（关掉该窗口不影响主程序）
    func pane(_ pane: PaneViewController, openInNewWindow url: URL)
}

extension FileClipboard {
    static let markerType = NSPasteboard.PasteboardType(rawValue: "com.qspacelite.fileoperation")
}

/// 捕获「设置的修饰键 + 滚轮」，用于调整所在窗格的图标大小；普通滚轮交给 NSScrollView 正常滚动。
final class PaneScrollView: NSScrollView {
    weak var pane: PaneViewController?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(AppSettings.iconResizeModifier.flags) {
            pane?.activate()
            pane?.adjustIconSize(by: event.scrollingDeltaY)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

final class PaneContainerView: NSView {
    weak var pane: PaneViewController?

    override var acceptsFirstResponder: Bool { true }

    /// 让整个窗格（含工具栏与空白区）都能接收 fileURL 拖放，避免只能拖到表格行上才生效
    func enableFileDrop() {
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        pane?.validateExternalDrop(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        pane?.validateExternalDrop(sender) ?? []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        pane?.handleExternalDrop(sender) ?? false
    }

    override func mouseDown(with event: NSEvent) {
        pane?.activate()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        pane?.activate()
        super.rightMouseDown(with: event)
    }

}

final class IconCollectionView: NSCollectionView {
    var onDoubleClickItem: ((IndexPath) -> Void)?
    var onActivate: (() -> Void)?
    /// 单击：索引、点击前是否已选中、点击位置（用于“再点一次文件名即重命名”）
    var onSingleClickItem: ((IndexPath, Bool, NSPoint) -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?
    weak var pane: PaneViewController?
    /// Windows 风格 Shift 连续多选的锚点（上一次普通点击的 item）
    private var shiftAnchorItem: Int?

    /// 拖到本应用之外时同时允许复制与移动；播放器通常只接受 .copy
    override func draggingSession(_ session: NSDraggingSession,
                                  sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .move]
    }

    /// 目录/排序变化时重置 Shift 锚点
    func resetShiftAnchor() { shiftAnchorItem = nil }

    /// 图标视图的 NSCollectionViewDelegate 落点方法只在有效 item 上调用，拖到空白处会被拒。
    /// 直接重写拖拽目标方法，任何位置都转发给窗格处理，与列表模式行为一致。
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        pane?.validateExternalDrop(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        pane?.validateExternalDrop(sender) ?? []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // 若正好落在文件夹 item 上则进入该文件夹，否则交给窗格落到当前目录
        let point = convert(sender.draggingLocation, from: nil)
        if let indexPath = indexPathForItem(at: point),
           let url = pane?.urlForDisplayedItem(at: indexPath.item),
           (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return pane?.handleExternalDrop(sender, into: url) ?? false
        }
        return pane?.handleExternalDrop(sender) ?? false
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        let point = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: point)
        let wasSelected = indexPath.map { selectionIndexes.contains($0.item) } ?? false
        let shiftHeld = event.modifierFlags.contains(.shift)
        let commandHeld = event.modifierFlags.contains(.command)

        // Windows 风格：按住 Shift 点击时，选中锚点到当前 item 的连续区间
        if shiftHeld, let indexPath, let anchor = shiftAnchorItem {
            let low = min(anchor, indexPath.item)
            let high = max(anchor, indexPath.item)
            let paths = Set((low...high).map { IndexPath(item: $0, section: 0) })
            selectItems(at: paths, scrollPosition: [])
        } else {
            super.mouseDown(with: event)
            if let indexPath, !shiftHeld, !commandHeld {
                shiftAnchorItem = indexPath.item
            }
            if let indexPath, !shiftHeld, !commandHeld, !selectionIndexes.contains(indexPath.item) {
                selectItems(at: [indexPath], scrollPosition: [])
            }
        }

        guard let indexPath else { return }
        if event.clickCount == 2 {
            onDoubleClickItem?(indexPath)
        } else if event.clickCount == 1, !shiftHeld {
            onSingleClickItem?(indexPath, wasSelected, point)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onActivate?()
        if let onContextMenu {
            onContextMenu(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

final class PaneToolbarButton: TooltipButton {
    var onPress: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onPress?()
        super.mouseDown(with: event)
    }
}

/// 列标题：单击升序、双击降序；保留系统默认的列宽拖动行为
final class SortAwareTableHeaderView: NSTableHeaderView {
    var onHeaderClick: ((Int, Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let column = self.column(at: point)
        if column >= 0 { onHeaderClick?(column, event.clickCount) }
        super.mouseDown(with: event)
    }
}

final class PaneTableView: NSTableView {
    var onActivate: (() -> Void)?
    var onDoubleClickRow: ((Int) -> Void)?
    /// 单击：行号、点击前该行是否已选中、点击位置（用于“再点一次文件名即重命名”）
    var onSingleClickRow: ((Int, Bool, NSPoint) -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?
    /// Windows 风格 Shift 连续多选的锚点（上一次普通点击的行）
    private var shiftAnchorRow: Int?

    /// 拖到本应用之外时同时允许复制与移动；播放器通常只接受 .copy
    override func draggingSession(_ session: NSDraggingSession,
                                  sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .move]
    }

    /// 目录/排序变化时重置 Shift 锚点
    func resetShiftAnchor() { shiftAnchorRow = nil }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        let wasSelected = clickedRow >= 0 && selectedRowIndexes.contains(clickedRow)
        let shiftHeld = event.modifierFlags.contains(.shift)

        // Windows 风格：按住 Shift 点击时，选中锚点到当前行的连续区间。
        // 自己实现而不依赖 AppKit 原生行为，避免自定义 mouseDown 干扰导致失效。
        if shiftHeld, clickedRow >= 0, let anchor = shiftAnchorRow {
            let low = min(anchor, clickedRow)
            let high = max(anchor, clickedRow)
            selectRowIndexes(IndexSet(low...high), byExtendingSelection: false)
            // Shift 点击不触发重命名
        } else {
            super.mouseDown(with: event)
            if clickedRow >= 0 && !shiftHeld {
                shiftAnchorRow = clickedRow
            }
        }

        guard clickedRow >= 0 else { return }
        if event.clickCount == 2 {
            onDoubleClickRow?(clickedRow)
        } else if event.clickCount == 1, !shiftHeld {
            onSingleClickRow?(clickedRow, wasSelected, point)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onActivate?()
        if let onContextMenu {
            onContextMenu(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        onActivate?()
        super.otherMouseDown(with: event)
    }
}

/// 不拦截鼠标的图标/文字子视图：让拖拽事件穿透到 NSCollectionView，
/// 否则 NSImageView / NSTextField 会吞掉 mouseDown/dragging 导致无法拖放。
private final class IconPassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
private final class IconPassthroughTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class IconCollectionViewItem: NSCollectionViewItem {
    private let tileView = NSView()
    private let iconImageView = IconPassthroughImageView()
    private let nameLabel = IconPassthroughTextField(labelWithString: "")
    private var iconSizeConstraint: NSLayoutConstraint!
    private var paneIndex: Int = 0

    override func loadView() {
        view = tileView
        tileView.wantsLayer = true
        tileView.layer?.cornerRadius = 6

        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = NSFont.systemFont(ofSize: AppSettings.textSize(for: paneIndex))
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 2
        nameLabel.cell?.wraps = true
        nameLabel.cell?.isScrollable = false
        // Finder 风格：选中态用带圆角的图层背景，而不是 NSTextField 的直角绘制背景
        nameLabel.wantsLayer = true
        nameLabel.layer?.cornerRadius = 4
        nameLabel.layer?.masksToBounds = true
        nameLabel.drawsBackground = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        tileView.addSubview(iconImageView)
        tileView.addSubview(nameLabel)
        iconSizeConstraint = iconImageView.widthAnchor.constraint(equalToConstant: AppSettings.iconSize(for: paneIndex))
        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: tileView.topAnchor, constant: 6),
            iconImageView.centerXAnchor.constraint(equalTo: tileView.centerXAnchor),
            iconSizeConstraint,
            iconImageView.heightAnchor.constraint(equalTo: iconImageView.widthAnchor),
            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: tileView.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: tileView.trailingAnchor, constant: -2)
        ])
    }

    override var isSelected: Bool {
        didSet { updateHighlight() }
    }

    func configure(with item: FileItem, paneIndex: Int) {
        self.paneIndex = paneIndex
        iconSizeConstraint.constant = AppSettings.iconSize(for: paneIndex)
        let textSize = AppSettings.textSize(for: paneIndex)
        nameLabel.font = NSFont.systemFont(ofSize: textSize)
        iconImageView.image = item.thumbnail ?? item.icon
        nameLabel.stringValue = item.displayName
        updateHighlight()
    }

    /// 文件名区域（转换到指定视图坐标），用于判断是否点在名字上 / 定位重命名输入框
    func nameLabelFrame(in ancestor: NSView) -> NSRect {
        guard isViewLoaded else { return .zero }
        return nameLabel.convert(nameLabel.bounds, to: ancestor)
    }

    private func updateHighlight() {
        guard isViewLoaded else { return }
        if isSelected {
            // 参考 Finder：图标块用中性灰圆角高亮，不再绘制整块蓝色边框/填充
            tileView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            // 文件名使用蓝色圆角标签 + 白字
            nameLabel.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            nameLabel.textColor = .white
        } else {
            tileView.layer?.backgroundColor = NSColor.clear.cgColor
            nameLabel.layer?.backgroundColor = NSColor.clear.cgColor
            nameLabel.textColor = .labelColor
        }
    }
}

final class PaneViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    weak var delegate: PaneDelegate?
    let index: Int

    private(set) var currentURL: URL
    private var viewMode: PaneViewMode
    private var sortKey: PaneSortKey
    private var sortAscending = true
    private var forcedSortKey: PaneSortKey?
    private var forcedAscending: Bool?
    private var isApplyingSortDescriptors = false
    private var items: [FileItem] = []
    private var displayedItems: [FileItem] = []
    private var loadGeneration = 0
    private var historyStack: [URL]
    private var historyIndex = 0
    private var searchText = ""

    private let containerView = PaneContainerView()
    private let headerView = NSView()
    let toolbarView = NSView()
    private let navGroupView = NSView()
    private var backButton = NSButton()
    private var forwardButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let actionGroupView = NSView()
    private var actionButtons: [NSButton] = []
    private var iconModeButton = NSButton()
    private var listModeButton = NSButton()
    private var upButton = NSButton()
    private var sortButton = NSButton()
    private var newFolderButton = NSButton()
    private var trashButton = NSButton()
    private var terminalButton = NSButton()
    private var searchButton = NSButton()
    private var hiddenButton = NSButton()
    private var moreButton = NSButton()
    private var defaultPathButton = NSButton()
    private let pathBarView = PathBarView()
    private let pathControl = PanePathControl()
    private var pathMenuButton = NSButton()
    private let pathEditField = PathBashField()
    private var isPathBarEditing = false
    private var inlineRenameField: InlineRenameField?
    private var inlineRenameURL: URL?
    /// 上次点击文件的时间，用于识别“隔一小会儿再点一次文件名”的重命名手势
    private var lastClickMoment = Date.distantPast
    private let backgroundImageView = NSImageView()
    private let scrollView = PaneScrollView()
    private let tableView = PaneTableView()
    private let collectionView = IconCollectionView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")
    private var isActivePane = false
    private var lastWallpaperSize: NSSize = .zero
    private var lastGridWidth: CGFloat = 0
    /// 后台自动刷新：每 2 秒检查当前目录的修改时间，变化了才重新加载
    private var autoRefreshTimer: Timer?
    private var lastDirectoryStamp: Date?
    /// 整窗壁纸是否生效（生效时窗格背景透明，直接透出底层壁纸）
    private var workspaceWallpaperActive = false

    private let itemIdentifier = NSUserInterfaceItemIdentifier("IconItem")

    init(index: Int, url: URL) {
        self.index = index
        self.currentURL = url
        self.viewMode = AppSettings.viewModes()[index]
        self.sortKey = AppSettings.sortKeys()[index]
        self.historyStack = [url]
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        containerView.frame = NSRect(x: 0, y: 0, width: 1280, height: 760)
        view = containerView
        containerView.pane = self
        containerView.enableFileDrop()
    }

    override func viewDidLoad() {

        super.viewDidLoad()
        buildUI()
        applyViewMode()
        applyAppearanceSettings()
        navigate(to: currentURL, addToHistory: false)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyAppearanceSettings),
            name: .xspaceAppearanceChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenshotSaved(_:)),
            name: .xspaceScreenshotSaved,
            object: nil
        )
        startAutoRefresh()
    }

    // MARK: - 后台自动刷新

    private func startAutoRefresh() {
        autoRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.autoRefreshIfNeeded()
        }
        // 窗口菜单/弹出面板等 run loop 模式下也照常刷新
        RunLoop.main.add(timer, forMode: .common)
        autoRefreshTimer = timer
    }

    private func directoryStamp(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func autoRefreshIfNeeded() {
        // 正在输入/编辑时不打断用户；窗口隐藏时也无需刷新
        guard view.window?.isVisible == true,
              inlineRenameField == nil,
              !isPathBarEditing else { return }
        let stamp = directoryStamp(currentURL)
        guard stamp != lastDirectoryStamp else { return }
        lastDirectoryStamp = stamp
        refresh()
    }

    @objc private func screenshotSaved(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        statusLabel.stringValue = "截图已保存：\(url.lastPathComponent)"
    }

    deinit {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 界面搭建

    private func buildUI() {
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // 窗格内只保留路径栏；功能工具栏统一放在全局工具栏中，由 MainViewController 托管
        headerView.frame = NSRect(x: 0, y: 0, width: view.bounds.width, height: 38)
        headerView.autoresizingMask = []
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        containerView.addSubview(headerView)

        // 全局工具栏：左侧前进/后退 + 标题，右侧功能按钮组
        toolbarView.wantsLayer = true
        toolbarView.layer?.cornerRadius = 8
        toolbarView.layer?.borderWidth = 1
        toolbarView.layer?.borderColor = NSColor.clear.cgColor

        navGroupView.wantsLayer = true
        navGroupView.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.20).cgColor
        navGroupView.layer?.cornerRadius = 7
        toolbarView.addSubview(navGroupView)

        backButton = makeToolbarButton(symbol: "chevron.left", toolTip: "返回历史", action: #selector(goBack))
        forwardButton = makeToolbarButton(symbol: "chevron.right", toolTip: "前进历史", action: #selector(goForward))
        navGroupView.addSubview(backButton)
        navGroupView.addSubview(forwardButton)

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = .byTruncatingMiddle
        toolbarView.addSubview(titleLabel)

        searchField.placeholderString = "搜索当前文件夹"
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.isHidden = true
        toolbarView.addSubview(searchField)

        actionGroupView.wantsLayer = true
        actionGroupView.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.20).cgColor
        actionGroupView.layer?.cornerRadius = 7
        toolbarView.addSubview(actionGroupView)

        iconModeButton = makeToolbarButton(symbol: "square.grid.2x2", toolTip: "图标视图", action: #selector(switchToIconMode))
        listModeButton = makeToolbarButton(symbol: "list.bullet", toolTip: "列表视图", action: #selector(switchToListMode))
        upButton = makeToolbarButton(symbol: "arrow.up", toolTip: "上层目录", action: #selector(goUp))
        sortButton = makeToolbarButton(symbol: "arrow.up.arrow.down", toolTip: "排序方式", action: #selector(showSortMenu(_:)))
        newFolderButton = makeToolbarButton(symbol: "folder.badge.plus", toolTip: "新建文件夹", action: #selector(newFolder))
        trashButton = makeToolbarButton(symbol: "trash", toolTip: "移到废纸篓", action: #selector(trashSelected))
        terminalButton = makeToolbarButton(symbol: "terminal", toolTip: "在终端打开", action: #selector(openInTerminal))
        searchButton = makeToolbarButton(symbol: "magnifyingglass", toolTip: "搜索", action: #selector(toggleSearch))
        hiddenButton = makeToolbarButton(symbol: "eye.slash", toolTip: "显示/隐藏隐藏文件", action: #selector(toggleHiddenFiles))
        moreButton = makeToolbarButton(symbol: "ellipsis.circle", toolTip: "更多操作", action: #selector(showMoreMenu(_:)))
        defaultPathButton = makeToolbarButton(symbol: "pin", toolTip: "设为默认路径", action: #selector(setAsDefaultPath))

        // 显示顺序：功能按钮 → 隐藏 → 搜索 → 更多操作（最右）。
        // 窄窗格时优先隐藏中间的功能按钮，末尾三个（隐藏/搜索/更多）始终保留。
        actionButtons = [iconModeButton, listModeButton, sortButton, defaultPathButton,
                         upButton, newFolderButton, trashButton, terminalButton,
                         hiddenButton, searchButton, moreButton]
        actionButtons.forEach { actionGroupView.addSubview($0) }

        // 第二行：当前窗格路径面包屑
        pathBarView.wantsLayer = true
        pathBarView.layer?.cornerRadius = 7
        pathBarView.layer?.borderWidth = 1
        pathBarView.layer?.borderColor = NSColor.separatorColor.cgColor
        pathBarView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
        headerView.addSubview(pathBarView)

        pathControl.font = NSFont.systemFont(ofSize: 12)
        pathControl.target = self
        pathControl.action = #selector(pathControlClicked(_:))
        pathBarView.addSubview(pathControl)
        pathBarView.toolTip = "点击路径栏空白处：切换成 bash 格式路径，可框选或 ⌘C 复制"
        pathBarView.onEmptyAreaClick = { [weak self] in self?.showBashPath() }

        // 面包屑不显示时，这一行变成等宽 monospace 的 bash 路径，可直接框选 / ⌘C
        pathEditField.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        pathEditField.isEditable = true
        pathEditField.isSelectable = true
        pathEditField.isBezeled = false
        pathEditField.drawsBackground = true
        pathEditField.backgroundColor = NSColor.textBackgroundColor
        pathEditField.textColor = .labelColor
        pathEditField.focusRingType = .none
        pathEditField.wantsLayer = true
        pathEditField.layer?.cornerRadius = 5
        pathEditField.layer?.borderWidth = 1
        pathEditField.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
        pathEditField.target = self
        pathEditField.action = #selector(pathEditFieldCommitted(_:))
        pathEditField.onEscape = { [weak self] in self?.pathEditFieldCancelled() }
        pathEditField.isHidden = true
        pathBarView.addSubview(pathEditField)

        pathMenuButton = makeToolbarButton(symbol: "ellipsis", toolTip: "路径操作", action: #selector(showPathMenu(_:)))
        pathBarView.addSubview(pathMenuButton)

        backgroundImageView.frame = view.bounds
        backgroundImageView.imageScaling = .scaleAxesIndependently
        backgroundImageView.isHidden = true
        containerView.addSubview(backgroundImageView)

        scrollView.frame = NSRect(x: 0, y: 18, width: view.bounds.width, height: max(0, view.bounds.height - 90))
        scrollView.pane = self
        scrollView.autoresizingMask = []
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        containerView.addSubview(scrollView)

        statusLabel.font = NSFont.systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.autoresizingMask = []
        containerView.addSubview(statusLabel)

        configureTableView()
        configureCollectionView()
        applyViewMode()

        // 保证工具栏和状态栏始终盖在滚动区域之上
        containerView.addSubview(headerView)
        containerView.addSubview(statusLabel)
        headerView.translatesAutoresizingMaskIntoConstraints = true
        toolbarView.translatesAutoresizingMaskIntoConstraints = true
        pathBarView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = true
    }

    private func makeToolbarButton(symbol: String, toolTip: String, action: Selector) -> NSButton {
        let button = PaneToolbarButton(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = Symbol.image(symbol, fallback: "NSActionTemplate")
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        button.target = self
        button.action = action
        button.tooltipText = toolTip
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.onPress = { [weak self] in self?.activate() }
        return button
    }

    private func setActionButton(_ button: NSButton, highlighted: Bool) {
        button.layer?.backgroundColor = highlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.34).cgColor
            : NSColor.clear.cgColor
        button.contentTintColor = highlighted ? .controlAccentColor : .labelColor
    }

    private func configureTableView() {
        tableView.frame = scrollView.bounds
        tableView.onActivate = { [weak self] in self?.activate() }
        tableView.onDoubleClickRow = { [weak self] row in self?.openItem(at: row) }
        tableView.onSingleClickRow = { [weak self] row, wasSelected, _ in
            self?.handleRowRepeatClick(row: row, wasSelected: wasSelected)
        }
        tableView.onContextMenu = { [weak self] event in
            guard let self else { return }
            let point = self.tableView.convert(event.locationInWindow, from: nil)
            let row = self.tableView.row(at: point)
            let onBlank = row < 0
            if row >= 0, !self.tableView.selectedRowIndexes.contains(row) {
                self.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else if row < 0 {
                self.tableView.deselectAll(nil)
            }
            let screenPoint = self.view.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            self.contextMenu(onBlank: onBlank).popUp(positioning: nil, at: screenPoint, in: nil)
        }
        tableView.style = .plain
        tableView.rowHeight = max(24, AppSettings.textSize(for: index) + 12)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        // 列被拖动换位置或拖动列边界改宽度后，AppKit 不会重新布局单元格内的子视图。
        // 收到通知后立刻校正可见单元格，避免文件名与修改日期等文字跨列重叠。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tableViewColumnsDidChange(_:)),
            name: NSTableView.columnDidMoveNotification,
            object: tableView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tableViewColumnsDidChange(_:)),
            name: NSTableView.columnDidResizeNotification,
            object: tableView
        )
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

        let sortHeader = SortAwareTableHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 24))
        sortHeader.onHeaderClick = { [weak self] columnIndex, clickCount in
            guard let self,
                  columnIndex < self.tableView.tableColumns.count,
                  let key = PaneSortKey(rawValue: self.tableView.tableColumns[columnIndex].identifier.rawValue) else { return }
            self.forcedSortKey = key
            self.forcedAscending = clickCount < 2
        }
        tableView.headerView = sortHeader

        let definitions: [(String, String, CGFloat)] = [
            ("name", "名称", 460), ("modified", "修改日期", 127), ("kind", "类型", 100), ("size", "大小", 85)
        ]
        for (key, title, width) in definitions {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            column.title = title
            column.width = width
            column.minWidth = key == "name" ? 300 : (key == "modified" ? 30 : 60)
            column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true)
            tableView.addTableColumn(column)
        }
        // 窄窗格下优先压缩最后一列，尽量保持名称列的宽度
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.sortDescriptors = [NSSortDescriptor(key: sortKey.rawValue, ascending: true)]
    }

    /// 列顺序 / 列宽变化后，按单元格当前实际宽度重排文本，立即消除跨列重叠。
    @objc private func tableViewColumnsDidChange(_ notification: Notification) {
        guard viewMode == .list else { return }
        tableView.enumerateAvailableRowViews { rowView, _ in
            for columnIndex in tableView.tableColumns.indices {
                guard let cell = rowView.view(atColumn: columnIndex) as? NSTableCellView else { continue }
                layoutFileCellText(cell)
            }
        }
        tableView.needsDisplay = true
    }

    /// 文本域随单元格一起伸缩；左边距由是否显示图标决定，宽度按当前单元格实际宽度计算。
    private func layoutFileCellText(_ cell: NSTableCellView) {
        let left: CGFloat = cell.imageView?.image == nil ? 6 : 26
        let width = max(20, cell.bounds.width - left - 4)
        cell.textField?.frame = NSRect(x: left, y: 3, width: width, height: max(18, cell.bounds.height - 6))
    }

    /// 自适应网格：按窗格可用宽度排布尽可能多的列，再把剩余宽度均分到每列，
    /// 这样图标间不留大片空白，同时一屏能显示更多文件；图标越大格子越大。
    private func iconCellSize(forWidth width: CGFloat) -> NSSize {
        let iconSize = AppSettings.iconSize(for: index)
        let inset: CGFloat = 8
        let spacing: CGFloat = 4
        let minCellWidth = iconSize + 16        // 图标 + 文件名的最小文字宽度
        let usable = max(minCellWidth, width - inset * 2)
        let columns = max(1, floor((usable + spacing) / (minCellWidth + spacing)))
        let cellWidth = floor((usable - (columns - 1) * spacing) / columns)
        // 高度按两行文件名的实际行高预留，字号变大时不会裁切文字
        let lineHeight = ceil(AppSettings.textSize(for: index) * 1.32)
        let cellHeight = iconSize + 14 + lineHeight * 2
        return NSSize(width: max(minCellWidth, cellWidth), height: cellHeight)
    }

    private func iconCellSize() -> NSSize {
        iconCellSize(forWidth: max(0, collectionView.bounds.width))
    }

    private func configureCollectionView() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = iconCellSize()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 6
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.pane = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(IconCollectionViewItem.self, forItemWithIdentifier: itemIdentifier)
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.onDoubleClickItem = { [weak self] indexPath in self?.openItem(at: indexPath.item) }
        collectionView.onSingleClickItem = { [weak self] indexPath, wasSelected, point in
            self?.handleItemRepeatClick(indexPath: indexPath, wasSelected: wasSelected, point: point)
        }
        collectionView.onActivate = { [weak self] in self?.activate() }
        collectionView.onContextMenu = { [weak self] event in
            guard let self else { return }
            let point = self.collectionView.convert(event.locationInWindow, from: nil)
            let indexPath = self.collectionView.indexPathForItem(at: point)
            let onBlank = indexPath == nil
            if let indexPath {
                if !self.collectionView.selectionIndexes.contains(indexPath.item) {
                    self.collectionView.selectItems(at: [indexPath], scrollPosition: [])
                }
            } else {
                self.collectionView.deselectAll(nil)
            }
            let screenPoint = self.view.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            self.contextMenu(onBlank: onBlank).popUp(positioning: nil, at: screenPoint, in: nil)
        }
    }

    private func applyViewMode() {
        let isList = viewMode == .list
        if isList {
            collectionView.removeFromSuperview()
            scrollView.documentView = tableView
            tableView.frame = scrollView.bounds
            tableView.reloadData()
        } else {
            tableView.removeFromSuperview()
            scrollView.documentView = collectionView
            collectionView.frame = scrollView.bounds
            collectionView.reloadData()
        }
        setActionButton(iconModeButton, highlighted: !isList)
        setActionButton(listModeButton, highlighted: isList)
        setActionButton(hiddenButton, highlighted: AppSettings.showHiddenFiles)
        statusLabel.stringValue = statusText()
    }

    /// 设置的修饰键 + 滚轮调整当前窗格图标大小（40-256），实时生效并持久化
    func adjustIconSize(by delta: CGFloat) {
        let current = AppSettings.iconSize(for: index)
        let step: CGFloat = delta >= 0 ? 6 : -6
        let next = min(256, max(40, current + step))
        guard next != current else { return }
        AppSettings.setIconSize(next, for: index)
        NotificationCenter.default.post(name: .xspaceAppearanceChanged, object: nil)
    }

    @objc func applyAppearanceSettings() {
        if let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
            layout.itemSize = iconCellSize()
            layout.minimumInteritemSpacing = 4
            layout.minimumLineSpacing = 6
            layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
            layout.invalidateLayout()
        }
        tableView.rowHeight = max(24, AppSettings.textSize(for: index) + 12)
        collectionView.reloadData()
        tableView.reloadData()
        updateWallpaper()
    }

    /// 单窗格壁纸由窗格自己渲染；整窗共享壁纸由 MainViewController 铺在窗口底层，
    /// 此时窗格背景透明，直接透出同一张图，不再做局部裁切。
    private func updateWallpaper() {
        if let panePath = AppSettings.paneWallpaperPath(for: index), !panePath.isEmpty {
            let blur = AppSettings.paneWallpaperBlur(for: index)
            let mode = AppSettings.paneWallpaperMode(for: index)
            backgroundImageView.image = WallpaperRenderer.image(
                path: panePath, blur: blur, mode: mode,
                size: NSRect(x: 0, y: 0, width: max(1, view.bounds.width), height: max(1, view.bounds.height)).size
            )
            backgroundImageView.isHidden = backgroundImageView.image == nil
        } else {
            backgroundImageView.image = nil
            backgroundImageView.isHidden = true
        }
        lastWallpaperSize = view.bounds.size
        updatePaneBackground()
    }

    /// 由整窗壁纸状态决定窗格是否透明：透明后窗格的图标/文件列表区域直接显示底层壁纸
    func setWorkspaceWallpaperActive(_ active: Bool) {
        guard workspaceWallpaperActive != active else { return }
        workspaceWallpaperActive = active
        updatePaneBackground()
    }

    /// 窗格有独立壁纸时保持不透明；否则在整窗壁纸生效时变透明
    private func updatePaneBackground() {
        let hasOwnWallpaper = !(AppSettings.paneWallpaperPath(for: index) ?? "").isEmpty
        let transparent = workspaceWallpaperActive && !hasOwnWallpaper
        containerView.layer?.backgroundColor = (transparent ? NSColor.clear : NSColor.windowBackgroundColor).cgColor
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let w = view.bounds.width
        let h = view.bounds.height

        backgroundImageView.frame = NSRect(x: 0, y: 0, width: w, height: h)
        if abs(w - lastWallpaperSize.width) > 1 || abs(h - lastWallpaperSize.height) > 1 {
            updateWallpaper()
        }
        headerView.frame = NSRect(x: 0, y: h - 38, width: w, height: 38)
        pathBarView.frame = NSRect(x: 8, y: 5, width: max(0, w - 16), height: 26)

        pathMenuButton.frame = NSRect(x: max(0, pathBarView.bounds.width - 28), y: 0, width: 24, height: 26)
        pathControl.frame = NSRect(x: 6, y: 0,
                                   width: max(60, pathBarView.bounds.width - 40), height: 26)
        if isPathBarEditing {
            pathEditField.frame = pathControl.frame.insetBy(dx: 0, dy: 2)
        }

        layoutToolbarContent()

        statusLabel.frame = NSRect(x: 10, y: 2, width: max(0, w - 20), height: 14)
        scrollView.frame = NSRect(x: 0, y: 18, width: w, height: max(0, h - 56))

        if viewMode == .list {
            tableView.frame = scrollView.bounds
        } else {
            collectionView.frame = scrollView.bounds
            // 窗格宽度变化后重新计算列数，让每一行尽量排满
            let gridWidth = collectionView.bounds.width
            if abs(gridWidth - lastGridWidth) > 1 {
                lastGridWidth = gridWidth
                (collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)?.invalidateLayout()
            }
        }
    }

    /// 由全局工具栏的可用宽度驱动，三个窗格各自的工具栏内容按同一宽度排布
    func layoutToolbarContent() {
        let w = toolbarView.bounds.width
        guard w > 0 else { return }

        navGroupView.frame = NSRect(x: 8, y: 4, width: 56, height: 26)
        backButton.frame = NSRect(x: 2, y: 0, width: 26, height: 26)
        forwardButton.frame = NSRect(x: 28, y: 0, width: 26, height: 26)

        // 右侧功能键按工具栏宽度自适应，窄窗口时保留最常用的几个
        let buttonW: CGFloat = 26
        let searchW: CGFloat = searchField.isHidden ? 0 : min(140, max(90, w * 0.22))
        let available = w - 64 - 16 - 50 - searchW - 16
        let visibleCount = min(actionButtons.count, max(4, Int(floor(available / (buttonW + 2)))))
        // 末尾三个（隐藏 / 搜索 / 更多操作）始终显示，空间不足时从中间开始收起
        let tailCount = 3
        let headCount = max(0, visibleCount - tailCount)
        var shownButtons: [NSButton] = []
        for (index, button) in actionButtons.enumerated() {
            let keep = index < headCount || index >= actionButtons.count - tailCount
            button.isHidden = !keep
            if keep { shownButtons.append(button) }
        }
        for (index, button) in shownButtons.enumerated() {
            button.frame = NSRect(x: 4 + CGFloat(index) * buttonW, y: 0, width: buttonW, height: 26)
        }
        let groupW = CGFloat(shownButtons.count) * buttonW + 8
        actionGroupView.frame = NSRect(x: w - groupW - 8, y: 4, width: groupW, height: 26)

        if !searchField.isHidden {
            searchField.frame = NSRect(x: actionGroupView.frame.minX - searchW - 6, y: 4,
                                       width: searchW, height: 26)
        }
        let titleLeft = navGroupView.frame.maxX + 8
        let titleRight = actionGroupView.frame.minX - 8 - (searchField.isHidden ? 0 : searchField.frame.width + 6)
        titleLabel.frame = NSRect(x: titleLeft, y: 4,
                                  width: max(40, titleRight - titleLeft), height: 26)
    }

    // MARK: - 数据加载与排序

    private func loadItems() {
        let token = loadGeneration
        let directory = currentURL
        let showHidden = AppSettings.showHiddenFiles
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .typeIdentifierKey],
                options: showHidden ? [] : [.skipsHiddenFiles]
            )) ?? []
            let loaded = urls.map { FileItem(url: $0) }
            DispatchQueue.main.async {
                guard token == self.loadGeneration else { return }
                self.items = loaded
                // 与本次加载结果对应的目录时间戳，供 2 秒自动刷新比对
                self.lastDirectoryStamp = self.directoryStamp(directory)
                self.applyFilterAndSort()
            }
        }
    }

    private func applyFilterAndSort() {
        var result = items
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        result.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            switch sortKey {
            case .name:
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return sortAscending ? order == .orderedAscending : order == .orderedDescending
            case .modified:
                let left = lhs.modified ?? .distantPast
                let right = rhs.modified ?? .distantPast
                return sortAscending ? left < right : left > right
            case .size:
                return sortAscending ? lhs.size < rhs.size : lhs.size > rhs.size
            case .kind:
                let order = lhs.kind.localizedStandardCompare(rhs.kind)
                return sortAscending ? order == .orderedAscending : order == .orderedDescending
            }
        }
        displayedItems = result
        // 列表内容变化后旧的 Shift 锚点已失效，重置避免跨目录误选
        tableView.resetShiftAnchor()
        collectionView.resetShiftAnchor()
        if viewMode == .list { tableView.reloadData() } else { collectionView.reloadData() }
        statusLabel.stringValue = statusText()
    }

    private var transientStatus: String?
    private var transientStatusUntil: Date?

    /// 在状态栏短暂显示一条提示（例如操作撤销结果），刷新列表后仍会保留到超时
    func showTransientStatus(_ text: String) {
        transientStatus = text
        transientStatusUntil = Date().addingTimeInterval(2.5)
        statusLabel.stringValue = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, self.transientStatus == text else { return }
            self.transientStatus = nil
            self.transientStatusUntil = nil
            self.statusLabel.stringValue = self.statusText()
        }
    }

    private func statusText() -> String {
        if let text = transientStatus, let until = transientStatusUntil, Date() < until { return text }
        let selected = selectedURLs().count
        let base = "\(displayedItems.count) 个项目"
        return selected > 0 ? "\(base) · 已选择 \(selected) 项" : base
    }

    @objc func refresh() {
        generationTick()
        loadItems()
    }

    private func generationTick() { loadGeneration += 1 }

    // MARK: - 导航

    func navigate(to url: URL, addToHistory: Bool = true) {
        endPathBarEditing()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            NSWorkspace.shared.open(url)
            return
        }
        if addToHistory, historyStack[historyIndex] != url {
            if historyIndex < historyStack.count - 1 {
                historyStack.removeSubrange((historyIndex + 1)...)
            }
            historyStack.append(url)
            historyIndex = historyStack.count - 1
        }
        currentURL = url
        pathControl.url = url
        titleLabel.stringValue = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        searchText = ""
        searchField.stringValue = ""
        generationTick()
        loadItems()
        updateNavigationButtons()
        delegate?.paneDidChangeState(self)
    }

    @objc func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        navigate(to: historyStack[historyIndex], addToHistory: false)
    }

    @objc func goForward() {
        guard historyIndex < historyStack.count - 1 else { return }
        historyIndex += 1
        navigate(to: historyStack[historyIndex], addToHistory: false)
    }

    @objc func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent.path != currentURL.path else { return }
        navigate(to: parent)
    }

    func canGoBack() -> Bool { historyIndex > 0 }
    func canGoForward() -> Bool { historyIndex < historyStack.count - 1 }

    private func updateNavigationButtons() {
        backButton.isEnabled = canGoBack()
        forwardButton.isEnabled = canGoForward()
        upButton.isEnabled = currentURL.deletingLastPathComponent().path != currentURL.path
    }

    @objc private func pathControlClicked(_ sender: NSPathControl) {
        activate()
        guard let url = sender.clickedPathItem?.url else { return }
        navigate(to: url)
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        activate()
        searchText = sender.stringValue
        applyFilterAndSort()
    }

    @objc private func switchToIconMode() { setViewMode(.icon) }
    @objc private func switchToListMode() { setViewMode(.list) }

    private func setViewMode(_ mode: PaneViewMode) {
        guard viewMode != mode else { return }
        viewMode = mode
        applyViewMode()
        delegate?.paneDidChangeState(self)
    }

    @objc func toggleViewMode() {
        setViewMode(viewMode == .list ? .icon : .list)
    }

    @objc private func toggleSearch() {
        if searchField.isHidden {
            searchField.isHidden = false
            view.window?.makeFirstResponder(searchField)
        } else if searchField.stringValue.isEmpty {
            searchField.isHidden = true
            searchText = ""
            applyFilterAndSort()
        } else {
            view.window?.makeFirstResponder(searchField)
        }
        view.needsLayout = true
    }

    @objc private func showSortMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let options: [(String, PaneSortKey, Selector)] = [
            ("按名称", .name, #selector(sortByName)),
            ("按修改日期", .modified, #selector(sortByModified)),
            ("按大小", .size, #selector(sortBySize)),
            ("按类型", .kind, #selector(sortByKind))
        ]
        for (title, key, action) in options {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.state = sortKey == key ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func showMoreMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let hasSelection = !selectedURLs().isEmpty
        menu.addItem(title: "在新窗格中打开", action: #selector(openInOtherPane), target: self, keyEquivalent: "").isEnabled = hasSelection
        menu.addItem(title: "在终端打开", action: #selector(openInTerminal), target: self, keyEquivalent: "")
        menu.addItem(title: "在访达中显示", action: #selector(revealInFinder), target: self, keyEquivalent: "")
        menu.addItem(title: "拷贝路径", action: #selector(copyCurrentPath), target: self, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(title: "全选", action: #selector(selectAllItems), target: self, keyEquivalent: "a")
        menu.addItem(title: "反选", action: #selector(invertSelection), target: self, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(title: AppSettings.showHiddenFiles ? "隐藏隐藏文件" : "显示隐藏文件",
                     action: #selector(toggleHiddenFiles), target: self, keyEquivalent: "")
        menu.addItem(title: "设置默认路径", action: #selector(setAsDefaultPath), target: self, keyEquivalent: "")
        menu.addItem(title: "刷新", action: #selector(refresh), target: self, keyEquivalent: "r")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func showPathMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(title: "拷贝当前路径", action: #selector(copyCurrentPath), target: self, keyEquivalent: "")
        menu.addItem(title: "在终端打开", action: #selector(openInTerminal), target: self, keyEquivalent: "")
        menu.addItem(title: "在访达中显示", action: #selector(revealInFinder), target: self, keyEquivalent: "")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc func copyCurrentPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentURL.path, forType: .string)
    }

    // MARK: - 地址栏 bash 路径

    /// 点击路径栏空白处：面包屑就地切换成 bash 格式的路径文本，
    /// 用户可自行框选或用 ⌘C 复制；回车 / Esc / 点击别处恢复面包屑。
    @objc func showBashPath() {
        delegate?.paneDidBecomeActive(self)
        isPathBarEditing = true
        pathEditField.stringValue = ShellPath.bashQuoted(currentURL.path)
        pathControl.isHidden = true
        pathEditField.isHidden = false
        pathEditField.frame = pathControl.frame.insetBy(dx: 0, dy: 2)
        guard let window = view.window else { return }
        window.makeFirstResponder(pathEditField)
        // 默认全选，方便直接 ⌘C；想复制局部就自己拖选
        pathEditField.currentEditor()?.selectedRange = NSRange(location: 0, length: (pathEditField.stringValue as NSString).length)
        statusLabel.stringValue = "bash 路径 · 可框选或 ⌘C 复制，回车/Esc 返回"
    }

    /// 恢复面包屑显示
    func endPathBarEditing() {
        guard isPathBarEditing else { return }
        isPathBarEditing = false
        pathEditField.isHidden = true
        pathControl.isHidden = false
    }

    @objc private func pathEditFieldCommitted(_ sender: NSTextField) {
        let typed = ShellPath.unescape(sender.stringValue)
        endPathBarEditing()
        var isDirectory: ObjCBool = false
        if !typed.isEmpty,
           FileManager.default.fileExists(atPath: typed, isDirectory: &isDirectory),
           isDirectory.boolValue {
            navigate(to: URL(fileURLWithPath: typed))
        } else {
            statusLabel.stringValue = "路径已恢复显示"
        }
    }

    @objc private func pathEditFieldCancelled() {
        endPathBarEditing()
        statusLabel.stringValue = statusText()
    }

    @objc func setAsDefaultPath() {
        AppSettings.setDefaultPath(currentURL, for: index)
        statusLabel.stringValue = "已将当前目录设为默认路径"
        delegate?.paneDidChangeState(self)
    }

    func setActive(_ active: Bool) {
        guard isActivePane != active else { return }
        isActivePane = active
        toolbarView.layer?.borderColor = active
            ? NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor
            : NSColor.clear.cgColor
        pathBarView.layer?.borderColor = active
            ? NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            : NSColor.separatorColor.cgColor
        pathBarView.layer?.backgroundColor = active
            ? NSColor.controlBackgroundColor.withAlphaComponent(0.70).cgColor
            : NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
        titleLabel.textColor = active ? .labelColor : .secondaryLabelColor
    }

    @objc func sortByName() { setSortKey(.name) }
    @objc func sortByModified() { setSortKey(.modified) }
    @objc func sortBySize() { setSortKey(.size) }
    @objc func sortByKind() { setSortKey(.kind) }

    private func setSortKey(_ key: PaneSortKey) {
        sortKey = key
        sortAscending = true
        applyFilterAndSort()
        isApplyingSortDescriptors = true
        tableView.sortDescriptors = [NSSortDescriptor(key: key.rawValue, ascending: true)]
        isApplyingSortDescriptors = false
        delegate?.paneDidChangeState(self)
    }

    // MARK: - 选择

    func selectedURLs() -> [URL] {
        if viewMode == .list {
            return tableView.selectedRowIndexes.compactMap { row in
                row < displayedItems.count ? displayedItems[row].url : nil
            }
        }
        return collectionView.selectionIndexes.compactMap { index in
            index < displayedItems.count ? displayedItems[index].url : nil
        }
    }

    /// 当前目录下所有可见项目（未选中任何项目时给批量重命名用）
    func allVisibleURLs() -> [URL] {
        displayedItems.map(\.url)
    }

    func focusSearchField() {
        activate()
        view.window?.makeFirstResponder(searchField)
    }

    func activate() {
        delegate?.paneDidBecomeActive(self)
        endPathBarEditing()
        commitInlineRename()
        let responder: NSResponder = viewMode == .list ? tableView : collectionView
        view.window?.makeFirstResponder(responder)
    }

    func select(url: URL) {
        guard let index = displayedItems.firstIndex(where: { $0.url == url }) else { return }
        if viewMode == .list {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else {
            collectionView.selectItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .centeredVertically)
        }
        statusLabel.stringValue = statusText()
    }

    @objc func selectAllItems() {
        if viewMode == .list { tableView.selectAll(nil) } else { collectionView.selectAll(nil) }
        statusLabel.stringValue = statusText()
    }

    @objc func invertSelection() {
        if viewMode == .list {
            var inverted = IndexSet()
            for i in 0..<displayedItems.count where !tableView.selectedRowIndexes.contains(i) { inverted.insert(i) }
            tableView.selectRowIndexes(inverted, byExtendingSelection: false)
        } else {
            var indexPaths: Set<IndexPath> = []
            for i in 0..<displayedItems.count where !collectionView.selectionIndexes.contains(i) {
                indexPaths.insert(IndexPath(item: i, section: 0))
            }
            collectionView.deselectAll(nil)
            collectionView.selectItems(at: indexPaths, scrollPosition: [])
        }
        statusLabel.stringValue = statusText()
    }

    // MARK: - 文件操作

    @objc func openSelected() {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        urls.forEach { open(url: $0) }
    }

    /// 双击时直接按点击位置打开，避免依赖异步selection状态
    private func openItem(at index: Int) {
        guard index >= 0, index < displayedItems.count else { return }
        open(url: displayedItems[index].url)
    }

    private func open(url: URL) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let isAppBundle = url.pathExtension.lowercased() == "app"

        if exists, isDirectory.boolValue, !isAppBundle {
            navigate(to: url)
            return
        }

        // 显式用 completion 拿到系统打开失败的原因，避免“双击没反应”
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(url, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                Dialog.alert(title: "无法打开", message: "\(url.lastPathComponent)：\(error.localizedDescription)", window: self?.view.window)
            }
        }
    }

    @objc func openInOtherPane() {
        guard let url = selectedURLs().first else { return }
        delegate?.pane(self, openInOtherPane: url)
    }

    /// 右键「新窗口打开」：仅对文件夹生效，弹出独立的单窗口
    @objc func openInNewWindow() {
        guard let url = selectedURLs().first else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        delegate?.pane(self, openInNewWindow: url)
    }

    @objc func newFolder() {
        let name = Dialog.textInput(title: "新建文件夹", message: "请输入文件夹名称：", defaultValue: "新建文件夹", confirmTitle: "创建", window: view.window) ?? ""
        guard !name.isEmpty else { return }
        if let url = FileOperations.createFolder(in: currentURL, named: name) {
            refresh()
            select(url: url)
        }
    }

    // MARK: - 就地重命名（Windows 资源管理器风格）

    /// F2 / 右键“重命名” / 隔一小会儿再点一次文件名，都在原位改，不弹对话框
    @objc func renameSelected() {
        guard let url = selectedURLs().first else { return }
        beginInlineRename(for: url)
    }

    /// 在文件名上盖一个输入框开始编辑，默认只选中主文件名（不含扩展名）
    func beginInlineRename(for url: URL) {
        // 先把上一个未提交的编辑收尾，再按最新数据定位
        commitInlineRename()
        endPathBarEditing()
        guard let itemIndex = displayedItems.firstIndex(where: { $0.url == url }) else { return }
        delegate?.paneDidBecomeActive(self)
        select(url: url)

        let isApp = url.pathExtension.lowercased() == "app"
        let fullName = url.lastPathComponent
        let baseName = isApp ? fullName : (fullName as NSString).deletingPathExtension

        guard let anchor = renameAnchor(for: itemIndex) else { return }
        let field = InlineRenameField(frame: anchor.frame)
        field.stringValue = fullName
        field.font = anchor.font
        field.alignment = anchor.alignment
        field.isBordered = false
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.drawsBackground = true
        field.backgroundColor = NSColor.textBackgroundColor
        field.textColor = .labelColor
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.target = self
        field.action = #selector(inlineRenameCommitted(_:))
        field.onCancel = { [weak self] in self?.cancelInlineRename() }
        field.wantsLayer = true
        field.layer?.cornerRadius = 3
        field.layer?.borderWidth = 1.5
        field.layer?.borderColor = NSColor.controlAccentColor.cgColor
        anchor.container.addSubview(field)
        inlineRenameField = field
        inlineRenameURL = url

        view.window?.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            // 只选中主文件名；.app 等整体选中
            let length = isApp ? (fullName as NSString).length : (baseName as NSString).length
            editor.selectedRange = NSRange(location: 0, length: length)
        }
        statusLabel.stringValue = "重命名：回车确认 · Esc 取消"
    }

    /// 找到“文件名”在哪个视图里、放在什么位置
    private func renameAnchor(for itemIndex: Int) -> (container: NSView, frame: NSRect, font: NSFont, alignment: NSTextAlignment)? {
        if viewMode == .list {
            // 列可能被用户拖动重排，按标识找“名称”列，别假定它始终是第 0 列
            let nameColumn = tableView.tableColumns.firstIndex { $0.identifier.rawValue == "name" } ?? 0
            guard let cell = tableView.view(atColumn: nameColumn, row: itemIndex, makeIfNecessary: true) as? NSTableCellView,
                  let text = cell.textField else { return nil }
            let font = text.font ?? NSFont.systemFont(ofSize: 13)
            // 输入框收紧到文字宽度（与资源管理器一致），超长名称再靠横向滚动
            let name = displayedItems[itemIndex].displayName
            let textWidth = (name as NSString).size(withAttributes: [.font: font]).width
            let width = min(text.frame.width, max(90, textWidth + 16))
            let frame = NSRect(x: text.frame.minX - 2,
                               y: text.frame.minY - 1,
                               width: width,
                               height: max(20, text.frame.height + 2))
            return (cell, frame, font, .left)
        }
        guard let iconItem = collectionView.item(at: IndexPath(item: itemIndex, section: 0)) as? IconCollectionViewItem else {
            return nil
        }
        let labelFrame = iconItem.nameLabelFrame(in: iconItem.view)
        let lineHeight = max(24, ceil(AppSettings.textSize(for: index) * 1.3) + 8)
        let fieldFrame = NSRect(x: labelFrame.minX - 2,
                               y: max(labelFrame.minY, labelFrame.maxY - lineHeight),
                               width: max(60, labelFrame.width + 4),
                               height: lineHeight)
        return (iconItem.view, fieldFrame, NSFont.systemFont(ofSize: AppSettings.textSize(for: index)), .center)
    }

    @objc private func inlineRenameCommitted(_ sender: NSTextField) {
        commitInlineRename(sender.stringValue)
    }

    /// 提交（无参数版本供点击别处 / 导航时调用）
    func commitInlineRename() {
        guard let field = inlineRenameField else { return }
        commitInlineRename(field.stringValue)
    }

    private func commitInlineRename(_ newName: String) {
        guard let field = inlineRenameField, let url = inlineRenameURL else { return }
        let hadFocus = (view.window?.firstResponder as? NSTextView)?.delegate as? NSTextField === field
        inlineRenameField = nil
        inlineRenameURL = nil
        field.removeFromSuperview()
        if hadFocus {
            let responder: NSResponder = viewMode == .list ? tableView : collectionView
            view.window?.makeFirstResponder(responder)
        }
        performRename(url, to: newName)
    }

    func cancelInlineRename() {
        guard let field = inlineRenameField else { return }
        let hadFocus = (view.window?.firstResponder as? NSTextView)?.delegate as? NSTextField === field
        inlineRenameField = nil
        inlineRenameURL = nil
        field.removeFromSuperview()
        if hadFocus {
            let responder: NSResponder = viewMode == .list ? tableView : collectionView
            view.window?.makeFirstResponder(responder)
        }
        statusLabel.stringValue = statusText()
    }

    private func performRename(_ url: URL, to newName: String) {
        var name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { statusLabel.stringValue = statusText(); return }
        // 应用程序包重命名时自动保留 .app 扩展名
        let isApp = url.pathExtension.lowercased() == "app"
        if isApp && (name as NSString).pathExtension.lowercased() != "app" { name += ".app" }
        guard name != url.lastPathComponent else { statusLabel.stringValue = statusText(); return }
        let destination = url.deletingLastPathComponent().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            Dialog.alert(title: "重命名失败", message: "已存在同名项目。", window: view.window)
            return
        }
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            FileUndoStack.shared.record("重命名 \(url.lastPathComponent)") {
                _ = UndoIO.move(destination, to: url)
            }
            // 就地替换数据，避免异步刷新之前选中态丢失
            let replacement = FileItem(url: destination)
            if let i = items.firstIndex(where: { $0.url == url }) { items[i] = replacement }
            if let i = displayedItems.firstIndex(where: { $0.url == url }) { displayedItems[i] = replacement }
            applyFilterAndSort()
            select(url: destination)
        } catch {
            Dialog.alert(title: "重命名失败", message: error.localizedDescription, window: view.window)
        }
    }

    /// 慢速双击重命名（Windows 里叫 "slow double-click" / 单击已选中项重命名）。
    ///
    /// Windows 判定参数：注册表 `HKCU\Control Panel\Mouse\DoubleClickSpeed`，默认 500ms，
    /// 表示「两次点击间隔小于它 = 双击（打开）；大于它 = 两次独立单击」。
    /// 慢速双击重命名正是利用后者：第一次单击选中，间隔超过双击阈值后再单击一次 → 重命名。
    /// macOS 里对应的系统参数是 `NSEvent.doubleClickInterval`（随用户在系统设置里的双击速度变化）。
    ///
    /// 关键修正：下限必须 >= 系统双击间隔。否则间隔落在「本代码下限 ~ 系统双击间隔」之间时，
    /// AppKit 会把第二次点击当成双击（clickCount==2）直接打开，永远走不到重命名分支。
    private func isRepeatClick(wasSelected: Bool) -> Bool {
        let now = Date()
        let delta = now.timeIntervalSince(lastClickMoment)
        lastClickMoment = now
        // 系统双击间隔 + 少量余量，确保第二次点击不会被 AppKit 判为双击
        let lowerBound = max(0.5, NSEvent.doubleClickInterval + 0.1)
        // 上限放宽到 5 秒：给「点一下 → 想一下 → 再点文件名」留足时间
        let upperBound: TimeInterval = 5.0
        return wasSelected && delta >= lowerBound && delta <= upperBound
    }

    /// 列表里再点一次同一行：进入就地重命名
    private func handleRowRepeatClick(row: Int, wasSelected: Bool) {
        guard row >= 0, row < displayedItems.count else { return }
        guard isRepeatClick(wasSelected: wasSelected) else { return }
        beginInlineRename(for: displayedItems[row].url)
    }

    /// 图标视图里再点一次文件名：进入就地重命名
    private func handleItemRepeatClick(indexPath: IndexPath, wasSelected: Bool, point: NSPoint) {
        guard indexPath.item < displayedItems.count else { return }
        guard isRepeatClick(wasSelected: wasSelected) else { return }
        guard let iconItem = collectionView.item(at: indexPath) as? IconCollectionViewItem,
              iconItem.nameLabelFrame(in: collectionView).contains(point) else { return }
        beginInlineRename(for: displayedItems[indexPath.item].url)
    }

    @objc func copySelected() { putSelectionOnPasteboard(move: false) }

    @objc func cutSelected() { putSelectionOnPasteboard(move: true) }

    private func putSelectionOnPasteboard(move: Bool) {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        FileClipboard.shared.urls = urls
        FileClipboard.shared.operation = move ? .move : .copy
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        pasteboard.setString(move ? "move" : "copy", forType: FileClipboard.markerType)
        statusLabel.stringValue = "已\(move ? "剪切" : "复制") \(urls.count) 个项目"
    }

    @objc func pasteHere() {
        let pasteboard = NSPasteboard.general
        var urls: [URL] = []
        var move = false
        if let marker = pasteboard.string(forType: FileClipboard.markerType),
           (marker == "copy" || marker == "move") {
            urls = FileClipboard.shared.urls
            move = marker == "move"
        } else {
            urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        }
        guard !urls.isEmpty else {
            Dialog.alert(title: "无法粘贴", message: "剪贴板中没有文件。", window: view.window)
            return
        }
        let result = FileOperations.copyItems(urls, into: currentURL, move: move)
        if move {
            pasteboard.clearContents()
            FileClipboard.shared.urls = []
        }
        refresh()
        result.first.map { select(url: $0) }
    }

    @objc func trashSelected() {
        trashSelectedItems(confirm: true)
    }

    func trashSelectedItems(confirm: Bool) {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        if confirm, AppSettings.confirmBeforeTrash {
            let message = urls.count == 1
                ? "确定要将“\(urls[0].lastPathComponent)”移到废纸篓吗？"
                : "确定要将选中的 \(urls.count) 个项目移到废纸篓吗？"
            guard Dialog.confirm(title: "移到废纸篓", message: message, confirmTitle: "移到废纸篓", window: view.window) else { return }
        }
        FileOperations.trashItems(urls)
        refresh()
    }

    @objc func deleteSelectedPermanently() {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        if AppSettings.confirmBeforeDelete {
            let message = urls.count == 1
                ? "确定要永久删除“\(urls[0].lastPathComponent)”吗？此操作不可恢复。"
                : "确定要永久删除选中的 \(urls.count) 个项目吗？此操作不可恢复。"
            guard Dialog.confirm(title: "直接删除", message: message, confirmTitle: "删除", window: view.window) else { return }
        }
        var failures: [String] = []
        var removed = 0
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            Dialog.alert(title: "删除失败", message: failures.joined(separator: "\n"), window: view.window)
        }
        // 永久删除无法撤销，清掉历史避免撤销到已经不存在的中间状态
        if removed > 0 { FileUndoStack.shared.clear() }
        refresh()
    }

    @objc func openAlwaysWith(_ sender: NSMenuItem) {
        guard let url = selectedURLs().first,
              let appURL = sender.representedObject as? URL else { return }
        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: contentType)
        NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration(),
                                completionHandler: nil)
        let appName = (Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? FileManager.default.displayName(atPath: appURL.path)
        statusLabel.stringValue = "已设为“\(appName)”打开"
    }

    @objc func computeHash(_ sender: NSMenuItem) {
        guard let url = selectedURLs().first,
              let raw = sender.representedObject as? String,
              let kind = HashKind(rawValue: raw) else { return }
        do {
            let value = try HashComputer.hash(url, kind: kind)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            Dialog.alert(title: "\(kind.rawValue) 哈希值",
                         message: "\(value)\n\n已复制到剪贴板。",
                         window: view.window)
        } catch {
            Dialog.alert(title: "计算哈希失败", message: error.localizedDescription, window: view.window)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    @objc func copyPath() {
        let urls = selectedURLs()
        guard !urlFirst(urls) else { return }
        let paths = urls.map(\.path).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    private func urlFirst(_ urls: [URL]) -> Bool { urls.isEmpty }

    @objc func openInTerminal() {
        guard let url = selectedURLs().first ?? Optional(currentURL) else { return }
        FileOperations.openInTerminal(url)
    }

    @objc func revealInFinder() {
        let urls = selectedURLs()
        NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [currentURL] : urls)
    }

    @objc func showInfo() {
        guard let url = selectedURLs().first else { return }
        FileInfoWindowController.show(for: url)
    }

    @objc func toggleHiddenFiles() {
        AppSettings.showHiddenFiles.toggle()
        setActionButton(hiddenButton, highlighted: AppSettings.showHiddenFiles)
        refresh()
    }

    /// “始终以此方式打开”子菜单：列出系统认可的应用，并把选中的应用设为该文件类型的默认打开方式
    private func alwaysOpenMenuItem(for urls: [URL]) -> NSMenuItem {
        let item = NSMenuItem(title: "始终以此方式打开", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        if let url = urls.first {
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
            let currentApp = NSWorkspace.shared.urlForApplication(toOpen: url)
            for appURL in apps {
                let bundle = Bundle(url: appURL)
                let appName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? FileManager.default.displayName(atPath: appURL.path)
                let appItem = NSMenuItem(title: appName,
                                         action: #selector(openAlwaysWith(_:)), keyEquivalent: "")
                appItem.target = self
                appItem.representedObject = appURL
                appItem.image = NSWorkspace.shared.icon(forFile: appURL.path)
                if currentApp?.standardizedFileURL == appURL.standardizedFileURL { appItem.state = .on }
                appMenu.addItem(appItem)
            }
            if apps.isEmpty {
                let emptyItem = NSMenuItem(title: "（没有可用应用）", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                appMenu.addItem(emptyItem)
            }
        }
        item.submenu = appMenu
        item.isEnabled = !urls.isEmpty && !(appMenu.items.first?.isEnabled == false)
        return item
    }

    private func hashMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "计算哈希值", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for kind in HashKind.allCases {
            let hashItem = NSMenuItem(title: kind.rawValue, action: #selector(computeHash(_:)), keyEquivalent: "")
            hashItem.target = self
            hashItem.representedObject = kind.rawValue
            menu.addItem(hashItem)
        }
        item.submenu = menu
        return item
    }

    /// 剪贴板中是否有可粘贴的文件（XSpace 内部复制/剪切，或系统文件 URL）
    private func clipboardHasFiles() -> Bool {
        let pasteboard = NSPasteboard.general
        if let marker = pasteboard.string(forType: FileClipboard.markerType),
           (marker == "copy" || marker == "move") {
            return !FileClipboard.shared.urls.isEmpty
        }
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        return !urls.isEmpty
    }

    /// 清理菜单首尾及连续的分隔符，避免出现多余横线
    private func sanitizeSeparators(in menu: NSMenu) {
        var kept: [NSMenuItem] = []
        for item in menu.items {
            if item.isSeparatorItem, kept.isEmpty || kept.last?.isSeparatorItem == true { continue }
            kept.append(item)
        }
        while kept.last?.isSeparatorItem == true { kept.removeLast() }
        menu.removeAllItems()
        kept.forEach { menu.addItem($0) }
    }

    /// - Parameter onBlank: 是否在空白处右键。空白处只显示「新建文件夹 / 粘贴 / 刷新」，
    ///   文件上右键则显示文件操作项且不含这三项；「粘贴」在剪贴板无文件时完全隐藏。
    private func contextMenu(onBlank: Bool = false) -> NSMenu {
        let menu = NSMenu()
        let urls = selectedURLs()
        let hasSelection = !urls.isEmpty
        let singleFile = urls.count == 1 && !isDirectory(urls[0])
        let canPaste = clipboardHasFiles()

        // 只在空白处右键显示的项
        let blankOnly: Set<ContextMenuItemID> = [.newFolder, .paste, .refresh]

        func add(_ title: String, _ action: Selector, _ key: String = "", enabled: Bool = true) {
            let item = menu.addItem(title: title, action: action, target: self, keyEquivalent: key)
            item.isEnabled = enabled
        }

        for id in AppSettings.contextMenuItems {
            if blankOnly.contains(id) {
                guard onBlank else { continue }              // 文件上右键不显示这三项
                if id == .paste && !canPaste { continue }    // 剪贴板无文件则完全隐藏「粘贴」
            } else if onBlank {
                continue                                     // 空白处右键只保留上面的三项
            }

            switch id {
            case .open:
                add("打开", #selector(openSelected), "\r", enabled: hasSelection)
            case .openAlways:
                menu.addItem(alwaysOpenMenuItem(for: urls))
            case .openInOtherPane:
                add("在新窗格中打开", #selector(openInOtherPane), enabled: hasSelection)
            case .openInNewWindow:
                add("新窗口打开", #selector(openInNewWindow), enabled: hasSelection && isDirectory(urls[0]))
            case .openInTerminal:
                add("在终端打开", #selector(openInTerminal))
            case .separatorAfterOpen, .separatorAfterHash, .separatorAfterRename,
                 .separatorAfterPaste, .separatorBeforeRefresh:
                menu.addItem(.separator())
            case .newFolder:
                add("新建文件夹", #selector(newFolder))
            case .deletePermanently:
                // 按用户要求不再标红，与其它菜单项保持一致
                add("直接删除", #selector(deleteSelectedPermanently), enabled: hasSelection)
            case .computeHash:
                let item = hashMenuItem()
                item.isEnabled = singleFile
                menu.addItem(item)
            case .rename:
                add("重命名", #selector(renameSelected), enabled: hasSelection)
            case .cut:
                add("剪切", #selector(cutSelected), "x", enabled: hasSelection)
            case .copy:
                add("复制", #selector(copySelected), "c", enabled: hasSelection)
            case .paste:
                add("粘贴到此处", #selector(pasteHere), "v")
            case .trash:
                add("移到废纸篓", #selector(trashSelected), enabled: hasSelection)
            case .copyPath:
                add("拷贝路径", #selector(copyPath), enabled: hasSelection)
            case .revealInFinder:
                add("在访达中显示", #selector(revealInFinder))
            case .showInfo:
                add("显示简介", #selector(showInfo), enabled: hasSelection)
            case .refresh:
                add("刷新", #selector(refresh), "r")
            case .sevenZip:
                // 压缩包右键显示解压组，其余显示压缩组；位置由偏好设置中的顺序决定
                guard hasSelection else { break }
                menu.addItem(.separator())
                menu.addItem(sevenZipMenuItem(for: urls))
            }
        }

        sanitizeSeparators(in: menu)
        return menu
    }

    // MARK: - 7-Zip 右键菜单

    private func sevenZipMenuItem(for urls: [URL]) -> NSMenuItem {
        let item = NSMenuItem(title: "7-Zip", action: nil, keyEquivalent: "")
        item.image = SevenZipIcon.archive
        let sub = NSMenu()
        let archives = urls.filter { SevenZip.isArchive($0) }

        func addSub(_ title: String, _ action: Selector, _ payload: [URL], icon: NSImage? = nil) {
            let subItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
            subItem.target = self
            subItem.representedObject = payload
            if let icon { subItem.image = icon }
            sub.addItem(subItem)
        }

        if !archives.isEmpty {
            // 右键对象包含压缩包：解压相关操作
            addSub("用 7-Zip 打开", #selector(zipOpenArchive(_:)), archives, icon: SevenZipIcon.view)
            addSub("解压文件…", #selector(zipExtractFiles(_:)), archives, icon: SevenZipIcon.extract)
            addSub("解压到 \"\(archives[0].deletingPathExtension().lastPathComponent)\"",
                   #selector(zipExtractToFolder(_:)), archives, icon: SevenZipIcon.extractTo)
            addSub("解压到当前文件夹", #selector(zipExtractHere(_:)), archives, icon: SevenZipIcon.extract)
        } else {
            // 普通文件/文件夹：压缩相关操作
            addSub("添加到压缩文件…", #selector(zipAddToArchive(_:)), urls, icon: SevenZipIcon.add)
            addSub("添加到 \"\(currentURL.lastPathComponent)\"",
                   #selector(zipQuickAdd(_:)), urls, icon: SevenZipIcon.add)
        }
        item.submenu = sub
        return item
    }

    private func zipURLs(from sender: Any?) -> [URL] {
        (sender as? NSMenuItem)?.representedObject as? [URL] ?? []
    }

    @objc private func zipAddToArchive(_ sender: NSMenuItem) {
        let urls = zipURLs(from: sender)
        guard !urls.isEmpty else { return }
        let panel = SevenZipCompressPanel(directory: currentURL, defaultBaseName: currentURL.lastPathComponent)
        panel.onConfirm = { [weak self] archive, options in
            guard let self else { return }
            let result = SevenZip.compress(urls, to: archive, options: options)
            if result.ok {
                self.statusLabel.stringValue = "已创建压缩包：\(archive.lastPathComponent)"
                self.refresh()
            } else {
                Dialog.alert(title: "压缩失败", message: result.stderr, window: self.view.window)
            }
        }
        panel.run()
    }

    @objc private func zipQuickAdd(_ sender: NSMenuItem) {
        let urls = zipURLs(from: sender)
        guard !urls.isEmpty else { return }
        var options = SevenZip.CompressOptions()
        options.format = AppSettings.sevenZipFormat
        options.level = AppSettings.sevenZipLevel
        let archive = SevenZip.defaultArchiveURL(in: currentURL, ext: options.fileExtension)
        let result = SevenZip.compress(urls, to: archive, options: options)
        if result.ok {
            statusLabel.stringValue = "已创建压缩包：\(archive.lastPathComponent)"
            refresh()
        } else {
            Dialog.alert(title: "压缩失败", message: result.stderr, window: view.window)
        }
    }

    @objc private func zipOpenArchive(_ sender: NSMenuItem) {
        guard let archive = zipURLs(from: sender).first else { return }
        let browser = ArchiveBrowserController(archive: archive)
        browser.showWindow(nil)
        browser.open { ok, message in
            if !ok {
                Dialog.alert(title: "打开压缩包失败", message: message)
            }
        }
    }

    @objc private func zipExtractFiles(_ sender: NSMenuItem) {
        guard let archive = zipURLs(from: sender).first else { return }
        let base = archive.deletingPathExtension().lastPathComponent
        let panel = SevenZipExtractPanel(initialPath: archive.deletingLastPathComponent()
            .appendingPathComponent(base).path)
        panel.onConfirm = { [weak self] destination, password in
            guard let self else { return }
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let result = SevenZip.extract(archive, to: destination, password: password)
            if result.ok {
                self.statusLabel.stringValue = "已解压到：\(destination.lastPathComponent)"
                self.refresh()
            } else {
                Dialog.alert(title: "解压失败", message: result.stderr, window: self.view.window)
            }
        }
        panel.run()
    }

    @objc private func zipExtractToFolder(_ sender: NSMenuItem) {
        guard let archive = zipURLs(from: sender).first else { return }
        let base = archive.deletingPathExtension().lastPathComponent
        let destination = archive.deletingLastPathComponent().appendingPathComponent(base)
        let result = SevenZip.extract(archive, to: destination)
        if result.ok {
            statusLabel.stringValue = "已解压到：\(base)"
            refresh()
        } else {
            Dialog.alert(title: "解压失败", message: result.stderr, window: view.window)
        }
    }

    @objc private func zipExtractHere(_ sender: NSMenuItem) {
        guard let archive = zipURLs(from: sender).first else { return }
        let destination = archive.deletingLastPathComponent()
        let result = SevenZip.extract(archive, to: destination)
        if result.ok {
            statusLabel.stringValue = "已解压到当前文件夹"
            refresh()
        } else {
            Dialog.alert(title: "解压失败", message: result.stderr, window: view.window)
        }
    }

    // MARK: - NSTableView 数据源 / 代理

    func numberOfRows(in tableView: NSTableView) -> Int { displayedItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < displayedItems.count, let column = tableColumn else { return nil }
        let item = displayedItems[row]
        // 每一列使用独立复用标识：列被拖动重排后不会拿另一列的单元格来用，
        // 避免图标/文字宽度沿用旧列的数据。
        let cellID = column.identifier
        let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView ?? {
            let newCell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            newCell.identifier = cellID
            let imageView = NSImageView(frame: NSRect(x: 4, y: 2, width: 18, height: 18))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            newCell.addSubview(imageView)
            newCell.imageView = imageView
            let text = NSTextField(labelWithString: "")
            text.frame = NSRect(x: 26, y: 3, width: 170, height: 18)
            text.lineBreakMode = .byTruncatingMiddle
            text.autoresizingMask = [.width]   // 列宽变化时文字域跟着单元格伸缩
            newCell.addSubview(text)
            newCell.textField = text
            return newCell
        }()
        switch column.identifier.rawValue {
        case "name":
            cell.imageView?.image = item.icon
            cell.textField?.stringValue = item.displayName
        case "modified":
            cell.imageView?.image = nil
            cell.textField?.stringValue = item.modified.map { DateFormatterStore.medium.string(from: $0) } ?? "--"
        case "size":
            cell.imageView?.image = nil
            cell.textField?.stringValue = item.isDirectory ? "--" : FileSizeFormatter.string(item.size)
        default:
            cell.imageView?.image = nil
            cell.textField?.stringValue = item.kind
        }
        layoutFileCellText(cell)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        statusLabel.stringValue = statusText()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isApplyingSortDescriptors else { return }
        let key = forcedSortKey?.rawValue ?? tableView.sortDescriptors.first?.key
        let ascending = forcedAscending ?? tableView.sortDescriptors.first?.ascending ?? true
        forcedSortKey = nil
        forcedAscending = nil
        guard let key, let sort = PaneSortKey(rawValue: key) else { return }
        sortKey = sort
        sortAscending = ascending
        isApplyingSortDescriptors = true
        tableView.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        isApplyingSortDescriptors = false
        applyFilterAndSort()
        delegate?.paneDidChangeState(self)
    }

    func tableView(_ tableView: NSTableView, menuForEvent event: NSEvent) -> NSMenu? {
        let point = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: point)
        let onBlank = row < 0
        if row >= 0, !tableView.selectedRowIndexes.contains(row) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if row < 0 {
            tableView.deselectAll(nil)
        }
        return contextMenu(onBlank: onBlank)
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < displayedItems.count else { return nil }
        return displayedItems[row].url.dragPasteboardItem
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        if info.draggingPasteboard.string(forType: SevenZip.archiveDragMarker) == "1" { return .copy }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        return performDrop(info: info, row: row)
    }

    /// 整个窗格级别的拖放校验（用于容器视图接收非表格区域的拖放）
    func validateExternalDrop(_ info: NSDraggingInfo) -> NSDragOperation {
        if info.draggingPasteboard.string(forType: SevenZip.archiveDragMarker) == "1" { return .copy }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }

    /// 供图标视图判断是否落在文件夹 item 上
    func urlForDisplayedItem(at index: Int) -> URL? {
        guard index >= 0, index < displayedItems.count else { return nil }
        return displayedItems[index].url
    }

    /// 整个窗格级别的拖放处理：落到当前目录
    func handleExternalDrop(_ info: NSDraggingInfo) -> Bool {
        handleExternalDrop(info, into: currentURL)
    }

    /// 整个窗格级别的拖放处理：落到指定目录（图标视图落在文件夹上时传入该文件夹）
    func handleExternalDrop(_ info: NSDraggingInfo, into destination: URL) -> Bool {
        let pasteboard = info.draggingPasteboard
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        let fromArchive = pasteboard.string(forType: SevenZip.archiveDragMarker) == "1"
        let results = FileOperations.copyItems(urls, into: destination,
                                               move: !fromArchive && !NSEvent.modifierFlags.contains(.option))
        refresh()
        results.first.map { select(url: $0) }
        return !results.isEmpty
    }

    private func performDrop(info: NSDraggingInfo, row: Int) -> Bool {
        let pasteboard = info.draggingPasteboard
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        var destination = currentURL
        if row >= 0, row < displayedItems.count, displayedItems[row].isDirectory {
            destination = displayedItems[row].url
        }
        // 从压缩包浏览窗口拖出的条目来自临时目录：一律复制，不能“移动”掉，否则无法继续拖放。
        let fromArchive = pasteboard.string(forType: SevenZip.archiveDragMarker) == "1"
        let moving = !fromArchive && !NSEvent.modifierFlags.contains(.option)
        let results = FileOperations.copyItems(urls, into: destination, move: moving)
        refresh()
        results.first.map { select(url: $0) }
        return !results.isEmpty
    }

    // MARK: - NSCollectionView 数据源 / 代理

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { displayedItems.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: itemIdentifier, for: indexPath)
        guard let iconItem = item as? IconCollectionViewItem, indexPath.item < displayedItems.count else { return item }
        iconItem.configure(with: displayedItems[indexPath.item], paneIndex: index)
        return iconItem
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        statusLabel.stringValue = statusText()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        statusLabel.stringValue = statusText()
    }

    func collectionView(_ collectionView: NSCollectionView, menuForEvent event: NSEvent) -> NSMenu? {
        let point = collectionView.convert(event.locationInWindow, from: nil)
        let indexPath = collectionView.indexPathForItem(at: point)
        let onBlank = indexPath == nil
        if let indexPath {
            if !collectionView.selectionIndexes.contains(indexPath.item) {
                collectionView.selectItems(at: [indexPath], scrollPosition: [])
            }
        } else {
            collectionView.deselectAll(nil)
        }
        return contextMenu(onBlank: onBlank)
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard indexPath.item < displayedItems.count else { return nil }
        return displayedItems[indexPath.item].url.dragPasteboardItem
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let urls = (draggingInfo.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        var destination = currentURL
        if indexPath.item < displayedItems.count, displayedItems[indexPath.item].isDirectory {
            destination = displayedItems[indexPath.item].url
        }
        let fromArchive = draggingInfo.draggingPasteboard.string(forType: SevenZip.archiveDragMarker) == "1"
        let results = FileOperations.copyItems(urls, into: destination,
                                               move: !fromArchive && !NSEvent.modifierFlags.contains(.option))
        refresh()
        results.first.map { select(url: $0) }
        return !results.isEmpty
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        iconCellSize(forWidth: max(0, collectionView.bounds.width))
    }

    // MARK: - 供菜单校验使用

    func stateValues() -> (mode: PaneViewMode, sort: PaneSortKey, url: URL) {
        (viewMode, sortKey, currentURL)
    }

    func setValues(mode: PaneViewMode? = nil, sort: PaneSortKey? = nil) {
        if let mode { viewMode = mode }
        if let sort { sortKey = sort }
        applyViewMode()
        applyFilterAndSort()
    }

    var paneViewMode: PaneViewMode { viewMode }
    var paneSortKey: PaneSortKey { sortKey }
}

private extension NSMenu {
    @discardableResult
    func addItem(title: String, action: Selector, target: AnyObject?, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        addItem(item)
        return item
    }
}

extension PaneViewController {
    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<IndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        if draggingInfo.draggingPasteboard.string(forType: SevenZip.archiveDragMarker) == "1" { return .copy }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }
}

/// 路径栏容器：点空白区域（面包屑右侧）时回调，用于弹出 bash 路径
final class PathBarView: NSView {
    var onEmptyAreaClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onEmptyAreaClick?()
    }
}

/// 面包屑路径控件：点中路径元件走原来的跳转逻辑，点空白区域不拦截（交给父视图）
final class PanePathControl: NSPathControl {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let cell = cell as? NSPathCell, !cell.pathComponentCells.isEmpty else { return nil }
        let local = convert(point, from: superview)
        for component in cell.pathComponentCells {
            if cell.rect(of: component, withFrame: bounds, in: self).contains(local) {
                return super.hitTest(point)
            }
        }
        return nil
    }
}

/// 地址栏切换成 bash 文本时使用的输入框：Esc 直接恢复面包屑
final class PathBashField: NSTextField {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

/// 就地重命名用的输入框：回车 / Tab 提交，Esc 取消
final class InlineRenameField: NSTextField {
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onCancel?()
            return
        case 36, 76, 48: // Return / 小键盘 Enter / Tab
            if let action, let target {
                NSApp.sendAction(action, to: target, from: self)
            }
            return
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
