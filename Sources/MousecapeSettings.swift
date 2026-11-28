import AppKit
import UniformTypeIdentifiers

/// 一个 Mousecape 光标主题（.cape）
struct MousecapeTheme {
    let url: URL
    let name: String
    let author: String
    let identifier: String
    let preview: NSImage?
}

/// 光标主题相关工具：目录、解析、启动自动应用
enum MousecapeThemes {
    static var directory: URL {
        URL(fileURLWithPath: MousecapeBridge.capesDirectory(), isDirectory: true)
    }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func loadAll() -> [MousecapeTheme] {
        ensureDirectory()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "cape" }
            .compactMap { parse($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func parse(_ url: URL) -> MousecapeTheme? {
        guard let dict = NSDictionary(contentsOf: url) else { return nil }
        let name = dict["CapeName"] as? String ?? url.deletingPathExtension().lastPathComponent
        let author = dict["Author"] as? String ?? "未知作者"
        let identifier = dict["Identifier"] as? String ?? ""
        return MousecapeTheme(url: url, name: name, author: author,
                              identifier: identifier, preview: previewImage(from: dict))
    }

    /// 取 Arrow 光标的第一帧作为列表缩略图。
    /// 动画帧现在存在纵向 sprite sheet 里，直接缩放整张图会变成一条竖纹，必须先裁出顶部的单帧。
    private static func previewImage(from dict: NSDictionary) -> NSImage? {
        guard let cursors = dict["Cursors"] as? [String: Any] else { return nil }
        let arrow = cursors["com.apple.coregraphics.Arrow"] as? [String: Any]
            ?? cursors.values.compactMap { $0 as? [String: Any] }.first
        guard let representations = arrow?["Representations"] as? [Any],
              let data = representations.first as? Data,
              let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = CGFloat(min(cg.width, cg.height))
        let crop = CGRect(x: 0, y: CGFloat(cg.height) - side, width: side, height: side)
        guard let topFrame = cg.cropping(to: crop) else { return nil }
        return NSImage(cgImage: topFrame, size: NSSize(width: 30, height: 30))
    }

    /// 统一的应用入口：VNC 兼容模式下只把 Normal 箭头压成首帧，其余光标保留动画。
    static func apply(theme url: URL) -> Bool {
        guard AppSettings.mousecapeVNCStatic else {
            return MousecapeBridge.applyCape(atPath: url.path)
        }
        guard let staticCape = staticCapeDictionary(from: url) else { return false }
        return MousecapeBridge.applyCapeDictionary(staticCape as? [AnyHashable: Any] ?? [:])
    }

    /// Normal（默认箭头）在 macOS 上的标识及其等效别名。VNC 下只有它会被整张 sprite sheet 画出来。
    private static let normalCursorIdentifiers: Set<String> = [
        "com.apple.coregraphics.Arrow",
        "com.apple.coregraphics.ArrowCtx",
        "com.apple.coregraphics.ArrowS",
        "com.apple.cursor.24"
    ]

    /// 只把 Normal 箭头裁成第一帧；其它动画光标原样保留。
    private static func staticCapeDictionary(from url: URL) -> NSDictionary? {
        guard let cape = NSMutableDictionary(contentsOf: url),
              let cursors = cape["Cursors"] as? [String: Any] else { return nil }
        var staticCursors: [String: Any] = [:]
        for (identifier, value) in cursors {
            guard normalCursorIdentifiers.contains(identifier),
                  var cursor = value as? [String: Any] else {
                staticCursors[identifier] = value
                continue
            }
            let frameCount = (cursor["FrameCount"] as? NSNumber)?.intValue ?? 1
            guard frameCount > 1, let reps = cursor["Representations"] as? [Any], !reps.isEmpty else {
                staticCursors[identifier] = value
                continue
            }
            // 旧格式：每帧一个 representation，直接取第一个；新格式：一张纵向 sprite sheet，裁顶部首帧。
            let first: Any? = reps.count >= frameCount
                ? reps.first
                : reps.first.flatMap { firstFramePNG(from: $0, frameCount: frameCount) }
            guard let first else {
                staticCursors[identifier] = value
                continue
            }
            cursor["FrameCount"] = 1
            cursor["Representations"] = [first]
            staticCursors[identifier] = cursor
        }
        cape["Cursors"] = staticCursors
        return cape
    }

    private static func firstFramePNG(from representation: Any, frameCount: Int) -> Data? {
        let cg: CGImage?
        if let data = representation as? Data {
            cg = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else if let image = representation as? NSImage {
            cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else {
            cg = nil
        }
        guard let cg, frameCount > 0 else { return nil }
        let frameHeight = cg.height / frameCount
        guard frameHeight > 0 else { return nil }
        // CGImage 原点在左下，sprite sheet 的第 0 帧在最上方。
        let rect = CGRect(x: 0, y: cg.height - frameHeight, width: cg.width, height: frameHeight)
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])
    }

    /// 首次启动时按用户设置恢复上次应用的主题
    static func autoApplyIfNeeded() {
        guard AppSettings.mousecapeAutoApply,
              let path = AppSettings.mousecapeThemePath,
              FileManager.default.fileExists(atPath: path) else { return }
        DispatchQueue.global(qos: .utility).async {
            _ = MousecapeThemes.apply(theme: URL(fileURLWithPath: path))
        }
    }
}

/// 全局设置 →「光标」页：管理 .cape 主题、应用/恢复系统光标
final class MousecapeSettingsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private var themes: [MousecapeTheme] = []
    private var selectedRow = -1
    private var applyButton: NSButton!
    private var deleteButton: NSButton!
    private var statusLabel: NSTextField!
    private var remapWindow: CursorRemapWindowController?
    private let tableView = NSTableView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
        reload()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    // MARK: - 界面

    private func buildUI() {
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

        // 状态卡片
        addSubview(SettingCardView(frame: NSRect(x: 16, y: 388, width: 528, height: 116)))
        addSubview(label("鼠标光标", frame: NSRect(x: 34, y: 476, width: 76, height: 20),
                        alignment: .right, font: titleFont))
        statusLabel = label("", frame: NSRect(x: 118, y: 476, width: 400, height: 20),
                            font: NSFont.systemFont(ofSize: 12, weight: .medium))
        addSubview(statusLabel)
        addSubview(note("兼容 Mousecape 的 .cape 主题；应用后立即在系统范围生效。",
                        frame: NSRect(x: 118, y: 452, width: 410, height: 18)))
        let reset = NSButton(title: "恢复系统默认", target: self, action: #selector(resetCursors))
        reset.frame = NSRect(x: 118, y: 410, width: 130, height: 28)
        reset.bezelStyle = .rounded
        addSubview(reset)
        let openDir = NSButton(title: "打开主题目录", target: self, action: #selector(openThemeDirectory))
        openDir.frame = NSRect(x: 256, y: 410, width: 130, height: 28)
        openDir.bezelStyle = .rounded
        addSubview(openDir)

        // 主题列表卡片
        addSubview(SettingCardView(frame: NSRect(x: 16, y: 172, width: 528, height: 200)))
        let scroll = NSScrollView(frame: NSRect(x: 28, y: 188, width: 504, height: 168))
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        addSubview(scroll)

        tableView.frame = NSRect(x: 0, y: 0, width: 504, height: 168)
        tableView.rowHeight = 42
        tableView.headerView = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: 504, height: 22))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openCursorEditor)
        tableView.style = .inset
        for (index, title) in ["", "名称", "作者"].enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col\(index)"))
            column.title = title
            column.width = [44, 270, 170][index]
            tableView.addTableColumn(column)
        }

        // 操作按钮：一行排开，INF 转换紧挨「导入 .cape」
        applyButton = makeButton("应用所选主题", NSRect(x: 28, y: 136, width: 104, height: 28),
                                 #selector(applySelectedTheme))
        addSubview(applyButton)
        let importButton = makeButton("导入 .cape", NSRect(x: 140, y: 136, width: 100, height: 28),
                                      #selector(importTheme))
        addSubview(importButton)
        let infButton = makeButton("INF → .cape", NSRect(x: 248, y: 136, width: 110, height: 28),
                                   #selector(importINFTheme))
        addSubview(infButton)
        deleteButton = makeButton("移除", NSRect(x: 366, y: 136, width: 72, height: 28),
                                  #selector(deleteTheme))
        addSubview(deleteButton)
        let refresh = makeButton("刷新", NSRect(x: 446, y: 136, width: 72, height: 28),
                                 #selector(reload))
        addSubview(refresh)

        // 选项卡片
        addSubview(SettingCardView(frame: NSRect(x: 16, y: 16, width: 528, height: 112)))
        let autoApply = NSButton(checkboxWithTitle: "启动时自动应用上次主题", target: self, action: #selector(toggleAutoApply(_:)))
        autoApply.frame = NSRect(x: 32, y: 94, width: 250, height: 20)
        autoApply.state = AppSettings.mousecapeAutoApply ? .on : .off
        autoApply.action = #selector(toggleAutoApply(_:))
        autoApply.target = self
        addSubview(autoApply)
        let leftHanded = NSButton(checkboxWithTitle: "左手模式（镜像光标）", target: self, action: #selector(toggleLeftHanded(_:)))
        leftHanded.frame = NSRect(x: 300, y: 94, width: 220, height: 20)
        leftHanded.state = MousecapeBridge.isLeftHanded() ? .on : .off
        leftHanded.action = #selector(toggleLeftHanded(_:))
        leftHanded.target = self
        addSubview(leftHanded)
        let vncStatic = NSButton(checkboxWithTitle: "VNC 兼容：Normal 箭头静态（仅首帧）", target: self, action: #selector(toggleVNCStatic(_:)))
        vncStatic.frame = NSRect(x: 32, y: 70, width: 330, height: 20)
        vncStatic.state = AppSettings.mousecapeVNCStatic ? .on : .off
        vncStatic.toolTip = "开启后只有 Normal 默认箭头取第一帧，其它光标仍保留动画。"
        addSubview(vncStatic)
        let launchAtLogin = NSButton(checkboxWithTitle: "开机自启动 XSpace", target: self, action: #selector(toggleLaunchAtLogin(_:)))
        launchAtLogin.frame = NSRect(x: 372, y: 70, width: 166, height: 20)
        launchAtLogin.state = LaunchAtLogin.isEnabled ? .on : .off
        launchAtLogin.toolTip = "登录后自动运行 XSpace；配合「启动时自动应用上次主题」即可自动换图标。"
        addSubview(launchAtLogin)
        addSubview(note("双击主题可逐个更换光标状态的 ANI；「INF → .cape」按右键安装.inf 批量转换并映射光标类型。",
                        frame: NSRect(x: 32, y: 48, width: 496, height: 16)))
        addSubview(note("自启动 + 自动应用 = 登录后自动换图标；VNC 勾选后仅 Normal 箭头取首帧，其余保留动画。",
                        frame: NSRect(x: 32, y: 34, width: 496, height: 16)))
        addSubview(note("核心代码：Alex Zielenski / Mousecape（个人非商业用途）；转换与界面为 XSpace 自研。",
                        frame: NSRect(x: 32, y: 20, width: 496, height: 16)))
    }

    private func label(_ text: String, frame: NSRect, alignment: NSTextAlignment = .left,
                       font: NSFont = NSFont.systemFont(ofSize: 12)) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame
        field.font = font
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }

    private func note(_ text: String, frame: NSRect) -> NSTextField {
        let field = label(text, frame: frame, font: NSFont.systemFont(ofSize: 10))
        field.textColor = .tertiaryLabelColor
        return field
    }

    private func makeButton(_ title: String, _ frame: NSRect, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = frame
        button.bezelStyle = .rounded
        return button
    }

    // MARK: - 数据

    @objc func reload() {
        themes = MousecapeThemes.loadAll()
        selectedRow = tableView.selectedRow
        tableView.reloadData()
        updateControls()
    }

    private func updateControls() {
        let hasSelection = tableView.selectedRow >= 0 && tableView.selectedRow < themes.count
        applyButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        let applied = MousecapeBridge.appliedCapeIdentifier()
        if applied.isEmpty {
            statusLabel.stringValue = "当前：系统默认光标"
        } else if let theme = themes.first(where: { $0.identifier == applied }) {
            statusLabel.stringValue = "当前：\(theme.name)"
        } else {
            statusLabel.stringValue = "当前：\(applied)（外部应用）"
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { themes.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier.rawValue, themes.indices.contains(row) else { return nil }
        let theme = themes[row]
        let cell = NSTableCellView()
        switch identifier {
        case "col0":
            let imageView = NSImageView(frame: NSRect(x: 4, y: 5, width: 30, height: 30))
            imageView.image = theme.preview
            imageView.imageScaling = .scaleProportionallyUpOrDown
            cell.addSubview(imageView)
            cell.imageView = imageView
        case "col1":
            let field = NSTextField(labelWithString: theme.name)
            field.frame = NSRect(x: 2, y: 11, width: 260, height: 18)
            field.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            field.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(field)
            cell.textField = field
        default:
            let field = NSTextField(labelWithString: theme.author)
            field.frame = NSRect(x: 2, y: 11, width: 160, height: 18)
            field.font = NSFont.systemFont(ofSize: 11)
            field.textColor = .secondaryLabelColor
            field.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(field)
            cell.textField = field
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateControls()
    }

    // MARK: - 操作

    @objc private func openCursorEditor() {
        let row = tableView.selectedRow
        guard themes.indices.contains(row) else { return }
        let theme = themes[row]
        remapWindow = CursorRemapWindowController(
            theme: theme,
            onSaved: { [weak self] in self?.reload() },
            onClosed: { [weak self] in self?.remapWindow = nil }
        )
        remapWindow?.showWindow(nil)
        remapWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func applySelectedTheme() {
        let row = tableView.selectedRow
        guard themes.indices.contains(row) else { return }
        let theme = themes[row]
        if MousecapeThemes.apply(theme: theme.url) {
            AppSettings.mousecapeThemePath = theme.url.path
            updateControls()
        } else {
            Dialog.alert(title: "应用失败", message: "无法应用“\(theme.name)”，请确认该文件是有效的 .cape 主题。")
        }
    }

    @objc private func resetCursors() {
        MousecapeBridge.resetCursors()
        AppSettings.mousecapeThemePath = nil
        updateControls()
    }

    @objc private func importTheme() {
        let panel = NSOpenPanel()
        panel.title = "导入光标主题"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "cape")].compactMap { $0 }
        guard panel.runModal() == .OK else { return }
        MousecapeThemes.ensureDirectory()
        var imported = 0
        for url in panel.urls {
            let destination = MousecapeThemes.directory.appendingPathComponent(url.lastPathComponent)
            if destination.resolvesSymlink() == url.resolvesSymlink() { continue }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
                imported += 1
            } catch {
                Dialog.alert(title: "导入失败", message: "\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        reload()
        if imported > 0 {
            let first = panel.urls[0].lastPathComponent
            if let index = themes.firstIndex(where: { $0.url.lastPathComponent == first }) {
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        }
    }

    @objc private func importINFTheme() {
        let panel = NSOpenPanel()
        panel.title = "按 INF 批量转换光标"
        panel.message = "选择光标包里的右键安装.inf（如“~右键安装.inf”）。"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "inf")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        convertINF(url)
    }

    private func convertINF(_ url: URL) {
        do {
            finishConversion(try WindowsCursorConverter.convert(inf: url))
        } catch {
            Dialog.alert(title: "INF 转换失败", message: error.localizedDescription)
        }
    }

    private func finishConversion(_ result: WindowsCursorConverter.ConversionResult) {
        reload()
        if let index = themes.firstIndex(where: { $0.url.path == result.url.path }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        let skippedText = result.skipped > 0 ? "（跳过 \(result.skipped) 个缺失文件）" : ""
        Dialog.alert(title: "转换完成",
                     message: "已生成主题“\(result.themeName)”：\(result.cursorCount) 种光标、\(result.frameCount) 帧动画，写入 \(result.identifierCount) 个 macOS 光标标识\(skippedText)。可在列表中选中并应用。")
    }

    @objc private func deleteTheme() {
        guard themes.indices.contains(tableView.selectedRow) else { return }
        let theme = themes[tableView.selectedRow]
        let alert = NSAlert()
        alert.messageText = "移除主题"
        alert.informativeText = "确定要把“\(theme.name)”移到废纸篓吗？"
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: theme.url, resultingItemURL: nil)
            if AppSettings.mousecapeThemePath == theme.url.path {
                AppSettings.mousecapeThemePath = nil
            }
            reload()
        } catch {
            Dialog.alert(title: "移除失败", message: error.localizedDescription)
        }
    }

    @objc private func openThemeDirectory() {
        MousecapeThemes.ensureDirectory()
        NSWorkspace.shared.open(MousecapeThemes.directory)
    }

    @objc private func toggleAutoApply(_ sender: NSButton) {
        AppSettings.mousecapeAutoApply = sender.state == .on
    }

    @objc private func toggleLeftHanded(_ sender: NSButton) {
        MousecapeBridge.setLeftHanded(sender.state == .on)
        reapplyCurrentTheme()
    }

    @objc private func toggleVNCStatic(_ sender: NSButton) {
        AppSettings.mousecapeVNCStatic = sender.state == .on
        reapplyCurrentTheme()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        let enabled = sender.state == .on
        if !LaunchAtLogin.setEnabled(enabled) {
            sender.state = .off
            Dialog.alert(title: "设置失败",
                         message: "无法写入登录项。请确认 XSpace 已安装到 /Applications，或手动到「系统设置 → 通用 → 登录项与扩展」中添加。")
        }
    }

    private func reapplyCurrentTheme() {
        // 镜像热点 / 静态首帧切换都需要重新应用当前主题才能生效
        guard let path = AppSettings.mousecapeThemePath,
              !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        DispatchQueue.global(qos: .utility).async {
            _ = MousecapeThemes.apply(theme: url)
        }
    }
}

private extension URL {
    /// 用于比较两个 URL 是否指向同一文件（导入源与目标相同则跳过）
    func resolvesSymlink() -> URL {
        resolvingSymlinksInPath()
    }
}
