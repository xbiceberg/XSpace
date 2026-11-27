import Foundation
import AppKit

/// 未选中窗格的边框颜色：黑色
private let paneBorderColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1.0)

/// 选中（活动）窗格的边框颜色：偏黑的青色（深青绿）
private let activePaneBorderColor = NSColor(srgbRed: 0.06, green: 0.26, blue: 0.28, alpha: 1.0)

/// 重写分隔条绘制，避免系统默认灰色细线把两侧窗格边框切成双线
final class BorderedSplitView: NSSplitView {
    override func drawDivider(in rect: NSRect) {
        paneBorderColor.setFill()
        rect.fill()
    }
}

final class MainViewController: NSViewController, PaneDelegate, SidebarDelegate, NSSplitViewDelegate {
    private(set) var panes: [PaneViewController] = []
    private(set) var activePane: PaneViewController!

    /// 固定布局：「新窗口打开」弹出的独立单窗口使用；nil 表示跟随全局设置
    private let forcedLayout: PaneLayout?
    /// 初始打开目录（仅作用于第一个窗格）
    private let initialURL: URL?
    /// 是否为独立弹出窗口（关闭后释放，不影响主程序）
    let isStandalone: Bool
    /// 请求用独立单窗口打开某个目录（由 AppDelegate 接线）
    var onOpenInNewWindow: ((URL) -> Void)?

    private let sidebar = SidebarViewController()
    private let outerSplit = BorderedSplitView()
    /// 内容区容器：内部按布局动态挂载 split 树
    private let contentContainer = NSView()
    private var contentSplits: [BorderedSplitView] = []
    /// 已挂到全局工具栏上的窗格工具栏，重建布局时先清理
    private var paneToolbarViews: [NSView] = []

    private let globalToolbar = NSView()
    /// 整窗共享壁纸：一张图铺满工作区底层，窗格透明透出同一张图
    private let wallpaperView = NSImageView()
    private let globalTitleLabel = NSTextField(labelWithString: "全局设置")
    private var globalHomeButton = NSButton()
    private var globalSettingsButton = NSButton()
    /// 批量重命名窗口（每个窗口各自一份，关闭后释放）
    private var bulkRenameController: BulkRenameWindowController?

    /// 内容重建后需要按比例分配一次分割位置
    private var pendingSplitSetup = true

    init(layout: PaneLayout? = nil, initialURL: URL? = nil, standalone: Bool = false) {
        self.forcedLayout = layout
        self.initialURL = initialURL
        self.isStandalone = standalone
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 当前生效的布局
    var currentLayout: PaneLayout {
        forcedLayout ?? AppSettings.paneLayout
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 760))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sidebar.delegate = self

        outerSplit.isVertical = true
        outerSplit.dividerStyle = .thin
        outerSplit.delegate = self
        outerSplit.addArrangedSubview(sidebar.view)
        outerSplit.addArrangedSubview(contentContainer)

        view.addSubview(outerSplit)
        outerSplit.frame = view.bounds
        outerSplit.autoresizingMask = [.width, .height]

        // 整窗壁纸放在最底层，位于侧栏与窗格之下
        wallpaperView.imageScaling = .scaleAxesIndependently
        wallpaperView.imageFrameStyle = .none
        wallpaperView.isHidden = true
        view.addSubview(wallpaperView, positioned: .below, relativeTo: outerSplit)

        // 分栏容器透明，才能透出底层壁纸
        outerSplit.wantsLayer = true
        outerSplit.layer?.backgroundColor = NSColor.clear.cgColor
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor

        buildGlobalToolbar()
        view.addSubview(globalToolbar)

        let visible = AppSettings.sidebarVisible
        sidebar.view.isHidden = !visible

        buildPanes(for: currentLayout)
        updatePaneBorders()

        NotificationCenter.default.addObserver(
            self, selector: #selector(updateGlobalWallpaper),
            name: .xspaceAppearanceChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(layoutSettingChanged),
            name: .xspaceLayoutChanged, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.title = windowTitle()
        activePane.activate()
        DispatchQueue.main.async { [weak self] in self?.applySplitPositionsIfNeeded() }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let w = view.bounds.width
        let h = view.bounds.height
        let barHeight: CGFloat = 38
        globalToolbar.frame = NSRect(x: 0, y: h - barHeight, width: w, height: barHeight)
        outerSplit.frame = NSRect(x: 0, y: 0, width: w, height: max(0, h - barHeight))
        wallpaperView.frame = outerSplit.frame
        globalSettingsButton.frame = NSRect(x: w - 36, y: 6, width: 26, height: 26)
        globalHomeButton.frame = NSRect(x: w - 70, y: 6, width: 26, height: 26)
        contentContainer.subviews.first?.frame = contentContainer.bounds
        for pane in panes {
            // 右侧仅保留全局按钮（回到默认位置 / 设置）的窄间距
            pane.toolbarView.frame = NSRect(x: 8, y: 2, width: max(120, w - 86), height: 34)
            pane.layoutToolbarContent()
        }
        applySplitPositionsIfNeeded()
        updateGlobalWallpaper()
    }

    // MARK: - 窗格与布局构建

    /// 按布局创建窗格并重建内容区分割树
    private func buildPanes(for layout: PaneLayout) {
        let count = layout.paneCount
        let previousURLs = panes.map(\.currentURL)
        let previousActiveIndex = panes.firstIndex { $0 === activePane } ?? 0
        let savedURLs = AppSettings.paneURLs(count: count)

        var newPanes: [PaneViewController] = []
        for index in 0..<count {
            let url: URL
            if index == 0, let initialURL {
                url = initialURL
            } else if index < previousURLs.count {
                url = previousURLs[index]
            } else if index < savedURLs.count {
                url = savedURLs[index]
            } else {
                url = FileManager.default.homeDirectoryForCurrentUser
            }
            let pane = PaneViewController(index: index, url: url)
            pane.delegate = self
            newPanes.append(pane)
        }

        panes = newPanes
        activePane = panes[min(previousActiveIndex, panes.count - 1)]

        rebuildContentArea(for: layout)
        attachPaneToolbars()
        updatePaneBorders()
        view.window?.title = windowTitle()
        pendingSplitSetup = true
        view.layoutSubtreeIfNeeded()
    }

    /// 按布局搭建嵌套 split 树，挂到内容区容器
    private func rebuildContentArea(for layout: PaneLayout) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        contentSplits.removeAll()

        let root: NSView
        switch layout {
        case .single:
            root = panes[0].view
        case .twoRows:
            let split = makeSplit(vertical: false)
            panes.forEach { split.addArrangedSubview($0.view) }
            root = split
        case .twoColumns:
            let split = makeSplit(vertical: true)
            panes.forEach { split.addArrangedSubview($0.view) }
            root = split
        case .threeLeftOne:
            // 左一（整列）| 右侧上下各一
            let horizontal = makeSplit(vertical: true)
            let rightColumn = makeSplit(vertical: false)
            rightColumn.addArrangedSubview(panes[1].view)
            rightColumn.addArrangedSubview(panes[2].view)
            horizontal.addArrangedSubview(panes[0].view)
            horizontal.addArrangedSubview(rightColumn)
            root = horizontal
        case .threeLeftTwo:
            // 左侧上下各一 | 右一（整列）
            let horizontal = makeSplit(vertical: true)
            let leftColumn = makeSplit(vertical: false)
            leftColumn.addArrangedSubview(panes[0].view)
            leftColumn.addArrangedSubview(panes[1].view)
            horizontal.addArrangedSubview(leftColumn)
            horizontal.addArrangedSubview(panes[2].view)
            root = horizontal
        case .four:
            // 左右各一列，每列上下各一
            let horizontal = makeSplit(vertical: true)
            let leftColumn = makeSplit(vertical: false)
            let rightColumn = makeSplit(vertical: false)
            leftColumn.addArrangedSubview(panes[0].view)
            leftColumn.addArrangedSubview(panes[1].view)
            rightColumn.addArrangedSubview(panes[2].view)
            rightColumn.addArrangedSubview(panes[3].view)
            horizontal.addArrangedSubview(leftColumn)
            horizontal.addArrangedSubview(rightColumn)
            root = horizontal
        }

        contentContainer.addSubview(root)
        root.frame = contentContainer.bounds
        root.autoresizingMask = [.width, .height]
    }

    private func makeSplit(vertical: Bool) -> BorderedSplitView {
        let split = BorderedSplitView()
        split.isVertical = vertical
        split.dividerStyle = .thin
        split.delegate = self
        split.wantsLayer = true
        split.layer?.backgroundColor = NSColor.clear.cgColor
        split.autoresizingMask = [.width, .height]
        contentSplits.append(split)
        return split
    }

    /// 把各窗格工具栏挂到全局工具栏，只显示当前活动窗格的那一份
    private func attachPaneToolbars() {
        paneToolbarViews.forEach { $0.removeFromSuperview() }
        paneToolbarViews = panes.map { pane in
            _ = pane.view   // 确保 toolbar 已随 viewDidLoad 构建
            return pane.toolbarView
        }
        for toolbar in paneToolbarViews {
            toolbar.removeFromSuperview()
            globalToolbar.addSubview(toolbar)
        }
        globalTitleLabel.isHidden = true
        updateActiveToolbar()
    }

    /// 设置里切换布局时的响应（独立窗口不受影响）
    @objc private func layoutSettingChanged() {
        guard forcedLayout == nil else { return }
        buildPanes(for: AppSettings.paneLayout)
        view.layoutSubtreeIfNeeded()
        applySplitPositionsIfNeeded()
    }

    /// 全局壁纸：整张图片铺满整个工作区，窗格保持透明直接透出同一张图，
    /// 不做任何按窗格裁切，视觉上软件是一个整体。
    @objc private func updateGlobalWallpaper() {
        guard let path = AppSettings.globalWallpaperPath, !path.isEmpty else {
            wallpaperView.image = nil
            wallpaperView.isHidden = true
            panes.forEach { $0.setWorkspaceWallpaperActive(false) }
            sidebar.setWorkspaceWallpaperActive(false)
            return
        }
        let area = outerSplit.bounds.size
        guard area.width > 1, area.height > 1 else { return }
        let image = WallpaperRenderer.image(
            path: path,
            blur: AppSettings.globalWallpaperBlur,
            mode: AppSettings.globalWallpaperMode,
            size: area
        )
        wallpaperView.image = image
        wallpaperView.isHidden = image == nil
        panes.forEach { $0.setWorkspaceWallpaperActive(image != nil) }
        sidebar.setWorkspaceWallpaperActive(image != nil)
    }

    private func buildGlobalToolbar() {
        globalToolbar.wantsLayer = true
        globalToolbar.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.85).cgColor
        globalToolbar.layer?.borderWidth = 1
        globalToolbar.layer?.borderColor = NSColor.separatorColor.cgColor

        globalTitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        globalTitleLabel.textColor = .secondaryLabelColor
        globalToolbar.addSubview(globalTitleLabel)

        globalHomeButton = makeGlobalButton(symbol: "house", toolTip: "回到默认位置", action: #selector(goToDefaults))
        globalSettingsButton = makeGlobalButton(symbol: "gearshape", toolTip: "设置", action: #selector(showGlobalSettingsMenu(_:)))
        globalToolbar.addSubview(globalHomeButton)
        globalToolbar.addSubview(globalSettingsButton)

        globalTitleLabel.isHidden = true
    }

    private func makeGlobalButton(symbol: String, toolTip: String, action: Selector) -> NSButton {
        let button = TooltipButton(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = Symbol.image(symbol)
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        button.target = self
        button.action = action
        button.tooltipText = toolTip
        return button
    }

    @objc func goToDefaults() {
        let paths = AppSettings.defaultPaths()
        for (index, url) in paths.enumerated() where index < panes.count {
            panes[index].navigate(to: url)
        }
        activePane = panes[0]
        updatePaneBorders()
        view.window?.title = windowTitle()
    }

    /// 全局工具栏 / 菜单入口：只把活动窗格当前选中的项目交给批量重命名窗口。
    /// 没有选中项时打开空列表，不再自动带入整个目录或上次的文件。
    @objc func openBulkRename() {
        let candidates = activePane.selectedURLs()
        if let existing = bulkRenameController {
            // 窗口已开着：把当前选中的项目追加进去（merge 内部去重），再置前
            existing.appendFiles(candidates)
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = BulkRenameWindowController(files: candidates)
        controller.onClose = { [weak self] in self?.bulkRenameController = nil }
        controller.window?.center()
        // 明确让弹出窗口成为 keyWindow 并激活 App：
        // 否则焦点仍停留在文件管理器主窗口，菜单的 ⌘V 会触发文件粘贴而非窗口内文字粘贴。
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
        bulkRenameController = controller
    }

    @objc private func resetDefaultSizes() {
        for index in 0..<PaneLayout.maxPanes {
            AppSettings.setIconSize(64, for: index)
            AppSettings.setTextSize(12, for: index)
        }
        NotificationCenter.default.post(name: .xspaceAppearanceChanged, object: nil)
    }

    @objc private func showGlobalSettingsMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(title: "回到默认位置", action: #selector(goToDefaults), target: self, keyEquivalent: "")
        menu.addItem(title: "恢复内置默认路径", action: #selector(resetDefaultPaths), target: self, keyEquivalent: "")
        menu.addItem(title: "恢复图标默认尺寸", action: #selector(resetDefaultSizes), target: self, keyEquivalent: "")
        menu.addItem(title: "批量重命名选中项…", action: #selector(openBulkRename), target: self, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(title: AppSettings.sidebarVisible ? "隐藏侧边栏" : "显示侧边栏",
                     action: #selector(globalToggleSidebar), target: self, keyEquivalent: "")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func resetDefaultPaths() {
        AppSettings.resetDefaultPaths()
        goToDefaults()
    }

    @objc private func globalToggleSidebar() { toggleSidebar() }

    /// 首次布局后按比例划分各层 split；用户后续拖动不会被反复重置
    private func applySplitPositionsIfNeeded() {
        guard pendingSplitSetup, contentContainer.bounds.width > 200 else { return }
        pendingSplitSetup = false
        outerSplit.setPosition(AppSettings.sidebarVisible ? 200 : 0, ofDividerAt: 0)
        for split in contentSplits {
            split.layoutSubtreeIfNeeded()
            let count = split.arrangedSubviews.count
            guard count > 1 else { continue }
            let total = split.isVertical ? split.bounds.width : split.bounds.height
            guard total > 100 else { continue }
            for index in 1..<count {
                split.setPosition(total * CGFloat(index) / CGFloat(count), ofDividerAt: index - 1)
            }
        }
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === outerSplit {
            return sidebar.view.isHidden ? 0 : 160
        }
        return 160
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === outerSplit {
            return sidebar.view.isHidden ? 0 : 280
        }
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        return max(160, total - 160)
    }

    // MARK: - PaneDelegate / SidebarDelegate

    func splitViewDidResizeSubviews(_ notification: Notification) {
        updateGlobalWallpaper()
    }

    func splitView(_ splitView: NSSplitView, colorForDividerAt dividerIndex: Int) -> NSColor {
        paneBorderColor
    }

    func paneDidBecomeActive(_ pane: PaneViewController) {
        if activePane === pane { return }
        activePane = pane
        updatePaneBorders()
        view.window?.title = windowTitle()
    }

    func paneDidChangeState(_ pane: PaneViewController) {
        AppSettings.savePaneURLs(panes.map(\.currentURL))
        AppSettings.saveViewModes(panes.map(\.paneViewMode))
        AppSettings.saveSortKeys(panes.map(\.paneSortKey))
        if pane === activePane { view.window?.title = windowTitle() }
    }

    func pane(_ pane: PaneViewController, openInOtherPane url: URL) {
        let target = panes.first { $0 !== pane } ?? pane
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            target.navigate(to: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// 右键「新窗口打开」：交给 AppDelegate 弹出独立的单窗口
    func pane(_ pane: PaneViewController, openInNewWindow url: URL) {
        onOpenInNewWindow?(url)
    }

    func sidebar(_ sidebar: SidebarViewController, didSelect url: URL) {
        activePane.navigate(to: url)
        activePane.activate()
    }

    func sidebarCurrentURL(_ sidebar: SidebarViewController) -> URL { activePane.currentURL }

    func sidebarDidRequestAddBookmark(_ sidebar: SidebarViewController) {
        let url = activePane.currentURL
        var bookmarks = AppSettings.bookmarks
        if bookmarks.contains(url) {
            bookmarks.removeAll { $0 == url }
        } else {
            bookmarks.append(url)
        }
        AppSettings.bookmarks = bookmarks
        sidebar.rebuild()
    }

    func sidebarDidDropFiles(_ sidebar: SidebarViewController) {
        panes.forEach { $0.refresh() }
    }

    private func updateActiveToolbar() {
        for pane in panes {
            pane.toolbarView.isHidden = pane !== activePane
        }
    }

    private func windowTitle() -> String {
        "XSpace — \(activePane.currentURL.lastPathComponent)"
    }

    private func updatePaneBorders() {
        for pane in panes {
            let active = pane === activePane
            pane.view.wantsLayer = true
            pane.view.layer?.cornerRadius = 12
            pane.view.layer?.masksToBounds = true
            pane.view.layer?.borderWidth = 3
            pane.view.layer?.borderColor = (active ? activePaneBorderColor : paneBorderColor).cgColor
            pane.setActive(active)
        }
        updateActiveToolbar()
    }

    // MARK: - 菜单转发

    func goBack() { activePane.goBack() }
    func goForward() { activePane.goForward() }
    func goUp() { activePane.goUp() }
    func refresh() { activePane.refresh() }
    /// 撤销最近一次文件操作（⌘Z）：所有窗格一起刷新，避免其它窗格显示旧状态
    func undo() {
        guard let title = FileUndoStack.shared.undo() else {
            activePane.showTransientStatus("没有可撤销的操作")
            return
        }
        panes.forEach { $0.refresh() }
        activePane.showTransientStatus("已撤销：\(title)")
    }
    func newFolder() { activePane.newFolder() }
    func openSelected() { activePane.openSelected() }
    func renameSelected() { activePane.renameSelected() }
    func copySelected() { activePane.copySelected() }
    func cutSelected() { activePane.cutSelected() }
    func pasteHere() { activePane.pasteHere() }
    func trashSelected() { activePane.trashSelected() }
    func trashSelectedWithoutConfirm() { activePane.trashSelectedItems(confirm: false) }
    func selectAll() { activePane.selectAllItems() }
    func invertSelection() { activePane.invertSelection() }
    func toggleViewMode() { activePane.toggleViewMode() }
    func toggleHiddenFiles() { activePane.toggleHiddenFiles() }
    func sortByName() { activePane.sortByName() }
    func sortByModified() { activePane.sortByModified() }
    func sortBySize() { activePane.sortBySize() }
    func sortByKind() { activePane.sortByKind() }

    func toggleSidebar() {
        let visible = !AppSettings.sidebarVisible
        AppSettings.sidebarVisible = visible
        sidebar.view.isHidden = !visible
        outerSplit.setPosition(visible ? 200 : 0, ofDividerAt: 0)
    }

    func focusSearch() {
        activePane.focusSearchField()
    }

    func goToPath() {
        let path = Dialog.textInput(title: "前往路径", message: "输入文件夹路径：", defaultValue: activePane.currentURL.path, confirmTitle: "前往", window: view.window) ?? ""
        guard !path.isEmpty else { return }
        activePane.navigate(to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
    }

    func goHome() { activePane.navigate(to: FileManager.default.homeDirectoryForCurrentUser) }
    func goDesktop() { activePane.navigate(to: FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser) }
    func goDocuments() { activePane.navigate(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser) }
    func goDownloads() { activePane.navigate(to: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser) }
    func goApplications() { activePane.navigate(to: URL(fileURLWithPath: "/Applications")) }
    func goRoot() { activePane.navigate(to: URL(fileURLWithPath: "/")) }

    func focusPane(at index: Int) {
        guard index >= 0, index < panes.count else { return }
        panes[index].activate()
    }

    func addBookmark() { sidebarDidRequestAddBookmark(sidebar) }

    func resetPanes() {
        let defaults = AppSettings.defaultPaths()
        for (index, url) in defaults.enumerated() where index < panes.count {
            panes[index].navigate(to: url, addToHistory: false)
        }
        sidebar.rebuild()
    }
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
