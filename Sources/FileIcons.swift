import Foundation
import AppKit
import UniformTypeIdentifiers

/// 用户可在偏好设置中自定义的文件类型图标。
struct FileIconRule: Codable, Equatable {
    var ext: String
    var path: String
}

/// 内置图标库：与用户提供的“图标库”目录一一对应。
enum FileIconCatalog {
    /// 图标库「视频」目录中的全部扩展名（含音频、字幕等）
    static let mediaExtensions: [String] = [
        "3gp", "aac", "ac3", "ape", "ass", "avi", "dat", "divx", "dts", "flac",
        "flv", "m3u", "m3u8", "m4a", "mkv", "mod", "mov", "mp2", "mp3", "mp4",
        "mpeg", "mpg", "ogg", "rm", "rmvb", "srt", "sub", "swf", "ts", "vob",
        "wav", "wma", "wmv"
    ]

    /// 图标库「压缩包」目录中的全部扩展名，均有独立图标
    static let archiveExtensions: [String] = [
        "7z", "arj", "bz2", "cab", "cpio", "gz", "iso", "lha", "lzh",
        "rar", "tar", "tgz", "wim", "xz", "z", "zip", "zst"
    ]

    /// 图标库「其他」目录中的扩展名，放在设置页「自定义」分类里
    static let otherExtensions: [String] = [
        "bmp", "doc", "docx", "dmg", "pdf", "ppt", "pptx", "txt", "xls", "xlsx"
    ]

    /// 自定义分类中内置图标的数量，用于区分「还原」和「删除」操作
    static var builtinOtherCount: Int { otherExtensions.count }

    static func isKnown(_ ext: String) -> Bool {
        let key = ext.lowercased()
        return mediaExtensions.contains(key)
            || archiveExtensions.contains(key)
            || otherExtensions.contains(key)
    }

    static func isArchive(_ ext: String) -> Bool {
        return archiveExtensions.contains(ext.lowercased())
    }
}

/// 解析扩展名对应的图标：用户自定义优先，其次工程内置图标库。
enum FileIconResolver {
    private static let cache = NSCache<NSString, NSImage>()
    private static let lock = NSLock()
    private static let supportDir: URL? = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return base?.appendingPathComponent("XSpace/FileIcons", isDirectory: true)
    }()

    static func clearCache() {
        lock.lock()
        cache.removeAllObjects()
        lock.unlock()
    }

    static func image(for ext: String) -> NSImage? {
        let key = ext.lowercased()
        guard !key.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let url = iconURL(for: key), let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    /// 是否要为这个扩展名使用自定义图标（内置库或用户规则）
    static func hasRule(for ext: String) -> Bool {
        let key = ext.lowercased()
        return !key.isEmpty && (iconURL(for: key) != nil)
    }

    static func iconURL(for ext: String) -> URL? {
        let key = ext.lowercased()
        if let custom = AppSettings.fileIconOverrides[key],
           FileManager.default.fileExists(atPath: custom) {
            return URL(fileURLWithPath: custom)
        }
        if FileIconCatalog.isKnown(key),
           let url = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "FileIcons") {
            return url
        }
        return nil
    }

    /// 把用户选择的图片另存为应用内的 PNG，避免原文件被移动后图标失效。
    @discardableResult
    static func storeCustomIcon(_ source: NSImage, for ext: String) -> String? {
        guard let dir = supportDir else { return nil }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch { return nil }
        let url = dir.appendingPathComponent("\(ext).png")
        let canvas = NSSize(width: 256, height: 256)
        let image = NSImage(size: canvas)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: canvas))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        do {
            try data.write(to: url)
            clearCache()
            return url.path
        } catch { return nil }
    }
}

/// 把图标写进文件的 Finder 元信息，使访达与整个系统里的同类文件也显示该图标。
enum FileIconSystemApply {
    enum Scope: Int {
        case home
        case disk

        var title: String { self == .home ? "当前用户目录" : "整个磁盘" }

        var root: String {
            self == .home ? FileManager.default.homeDirectoryForCurrentUser.path : "/"
        }
    }

    private static var progress: IconApplyProgressController?

    static func chooseScope() -> Scope? {
        let alert = NSAlert()
        alert.messageText = "应用到整个系统"
        alert.informativeText = "会把当前设置的图标写入匹配文件的 Finder 图标信息，访达中也会显示。\n\n"
            + "当前用户目录：只处理个人文件（推荐）。\n"
            + "整个磁盘：扫描所有可读位置，可能耗时较久且会跳过系统保护目录。\n\n"
            + "之后新建的文件不会自动带上图标；如需撤销，可点「清除系统图标」。"
        alert.addButton(withTitle: "当前用户目录")
        alert.addButton(withTitle: "整个磁盘")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .home
        case .alertSecondButtonReturn: return .disk
        default: return nil
        }
    }

    static func apply(clear: Bool, window: NSWindow?) {
        guard let scope = chooseScope() else { return }
        let confirm = NSAlert()
        confirm.messageText = clear ? "清除系统图标" : "确认应用到整个系统"
        confirm.informativeText = clear
            ? "将清除 \(scope.title) 中匹配文件上由 XSpace 写入的自定义图标。"
            : "将修改 \(scope.title) 中所有匹配文件的 Finder 图标，数量可能很多。"
        confirm.addButton(withTitle: clear ? "清除" : "开始")
        confirm.addButton(withTitle: "取消")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let controller = IconApplyProgressController(title: clear ? "正在清除系统图标" : "正在应用系统图标")
        progress = controller
        controller.show()

        DispatchQueue.global(qos: .userInitiated).async {
            let targets = collectTargets(in: scope)
            DispatchQueue.main.async {
                var index = 0
                var succeeded = 0
                func step() {
                    autoreleasepool {
                        let end = min(index + 40, targets.count)
                        for target in targets[index..<end] {
                            guard let image = clear ? nil : FileIconResolver.image(for: target.ext) else { continue }
                            if NSWorkspace.shared.setIcon(image, forFile: target.path, options: []) {
                                succeeded += 1
                            }
                        }
                        index = end
                    }
                    controller.update(index, total: targets.count)
                    if index < targets.count {
                        DispatchQueue.main.async(execute: step)
                    } else {
                        controller.close()
                        progress = nil
                        let alert = NSAlert()
                        alert.messageText = clear ? "清除完成" : "应用完成"
                        alert.informativeText = "扫描到 \(targets.count) 个匹配文件，成功处理 \(succeeded) 个。"
                        alert.addButton(withTitle: "好")
                        if let window { alert.beginSheetModal(for: window) { _ in } }
                        else { alert.runModal() }
                    }
                }
                if targets.isEmpty {
                    controller.close()
                    progress = nil
                    let alert = NSAlert()
                    alert.messageText = "没有找到匹配文件"
                    alert.informativeText = "当前图标设置下，\(scope.title)中没有需要处理的文件。"
                    alert.addButton(withTitle: "好")
                    if let window { alert.beginSheetModal(for: window) { _ in } }
                    else { alert.runModal() }
                } else {
                    step()
                }
            }
        }
    }

    private struct Target { let path: String; let ext: String }

    private static func collectTargets(in scope: Scope) -> [Target] {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: scope.root)
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }
        var result: [Target] = []
        let skipTop: Set<String> = ["System", "private", "Volumes", "usr", "bin", "sbin", "opt", "dev", "etc", "var"]
        for case let url as URL in enumerator {
            let path = url.path
            let components = url.pathComponents
            if scope == .disk, components.count > 1, skipTop.contains(components[1]) { continue }
            if components.contains(where: { $0 == "Library" || $0 == "node_modules" || $0 == ".git" }) { continue }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard FileIconResolver.hasRule(for: ext) else { continue }
            result.append(Target(path: path, ext: ext))
        }
        return result
    }
}

final class IconApplyProgressController: NSObject {
    private let window: NSWindow
    private let indicator = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "正在准备文件…")

    init(title: String) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 116),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        super.init()
        label.frame = NSRect(x: 20, y: 66, width: 320, height: 18)
        label.font = NSFont.systemFont(ofSize: 12)
        window.contentView?.addSubview(label)
        indicator.frame = NSRect(x: 20, y: 32, width: 320, height: 20)
        indicator.style = .bar
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        window.contentView?.addSubview(indicator)
    }

    func show() { window.center(); window.makeKeyAndOrderFront(nil) }

    func update(_ value: Int, total: Int) {
        label.stringValue = "已处理 \(value) / \(total)"
        indicator.isIndeterminate = false
        indicator.minValue = 0
        indicator.maxValue = Double(max(total, 1))
        indicator.doubleValue = Double(value)
    }

    func close() { indicator.stopAnimation(nil); window.orderOut(nil) }
}

/// 偏好设置里的「图标」页：视音频 / 压缩 / 自定义三类。
final class IconSettingsView: NSView {
    private let segmented = NSSegmentedControl(labels: ["视音频", "压缩", "自定义"],
                                               trackingMode: .selectOne,
                                               target: nil,
                                               action: #selector(switchCategory(_:)))
    private let scrollView = NSScrollView()
    private let grid = FlippedView()
    private var category = 0
    private var cellViews: [NSView] = []
    private var observer: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        segmented.target = self
        segmented.setWidth(96, forSegment: 0)
        segmented.setWidth(96, forSegment: 1)
        segmented.setWidth(96, forSegment: 2)
        segmented.selectedSegment = 0
        segmented.frame = NSRect(x: 16, y: 474, width: 300, height: 26)
        addSubview(segmented)

        scrollView.frame = NSRect(x: 16, y: 100, width: 528, height: 366)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = grid
        addSubview(scrollView)

        let card = SettingCardView(frame: NSRect(x: 16, y: 14, width: 528, height: 74))
        addSubview(card)
        let hint = NSTextField(labelWithString: "自定义图标会立即在 XSpace 中显示；系统范围需要点下面的按钮写入文件图标。")
        hint.frame = NSRect(x: 34, y: 62, width: 492, height: 18)
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        addSubview(hint)

        let apply = NSButton(title: "应用到整个系统", target: self, action: #selector(applyToSystem))
        apply.frame = NSRect(x: 34, y: 28, width: 148, height: 28)
        apply.bezelStyle = .rounded
        addSubview(apply)
        let clear = NSButton(title: "清除系统图标", target: self, action: #selector(clearSystemIcons))
        clear.frame = NSRect(x: 190, y: 28, width: 120, height: 28)
        clear.bezelStyle = .rounded
        addSubview(clear)
        let reset = NSButton(title: "恢复内置图标", target: self, action: #selector(resetBuiltinIcons))
        reset.frame = NSRect(x: 318, y: 28, width: 120, height: 28)
        reset.bezelStyle = .rounded
        addSubview(reset)

        if let raw = ProcessInfo.processInfo.environment["XSPACE_ICON_CATEGORY"],
           let index = Int(raw), (0..<3).contains(index) {
            category = index
            segmented.selectedSegment = index
        }

        observer = NotificationCenter.default.addObserver(
            forName: .xspaceFileIconsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.reloadGrid() }
        reloadGrid()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private var currentExtensions: [String] {
        switch category {
        case 0: return FileIconCatalog.mediaExtensions
        case 1: return FileIconCatalog.archiveExtensions
        default: return FileIconCatalog.otherExtensions
            + AppSettings.customIconExtensions.filter { !FileIconCatalog.isKnown($0) }
        }
    }

    private func reloadGrid() {
        cellViews.forEach { $0.removeFromSuperview() }
        cellViews.removeAll()

        let exts = currentExtensions
        let columns = 4
        let cellWidth: CGFloat = 124
        let cellHeight: CGFloat = 92
        let rows = max(1, Int(ceil(Double(exts.count + (category == 2 ? columns : 0)) / Double(columns))))
        let gridHeight = CGFloat(rows) * cellHeight + 12
        grid.frame = NSRect(x: 0, y: 0, width: 528, height: gridHeight)

        if category == 2 {
            let add = NSButton(title: "+ 添加自定义类型", target: self, action: #selector(addCustomType))
            add.frame = NSRect(x: 8, y: 6, width: 232, height: 30)
            add.bezelStyle = .rounded
            grid.addSubview(add)
            cellViews.append(add)
        }

        for (index, ext) in exts.enumerated() {
            let slot = category == 2 ? index + columns : index
            let col = slot % columns
            let row = slot / columns
            let x = CGFloat(8) + CGFloat(col) * cellWidth
            let y = CGFloat(row) * cellHeight + 38
            let origin = NSPoint(x: x, y: y)
            let cell = IconCell(frame: NSRect(origin: origin, size: NSSize(width: cellWidth - 8, height: cellHeight - 8)))
            cell.ext = ext
            cell.imageView.image = FileIconResolver.image(for: ext)
            cell.nameLabel.stringValue = ext.uppercased()
            cell.changeButton.target = self
            cell.changeButton.action = #selector(changeIcon(_:))
            cell.changeButton.tag = index
            if category == 2 && index >= FileIconCatalog.builtinOtherCount {
                cell.resetButton.title = "删除"
                cell.resetButton.target = self
                cell.resetButton.action = #selector(removeCustomType(_:))
            } else {
                cell.resetButton.title = "还原"
                cell.resetButton.target = self
                cell.resetButton.action = #selector(resetIcon(_:))
            }
            cell.resetButton.tag = index
            grid.addSubview(cell)
            cellViews.append(cell)
        }
        grid.needsDisplay = true
    }

    @objc private func switchCategory(_ sender: NSSegmentedControl) {
        category = sender.selectedSegment
        reloadGrid()
    }

    @objc private func changeIcon(_ sender: NSButton) {
        let exts = currentExtensions
        guard exts.indices.contains(sender.tag) else { return }
        let ext = exts[sender.tag]
        guard let path = chooseIconFile() else { return }
        guard let image = NSImage(contentsOf: URL(fileURLWithPath: path)) else {
            Dialog.alert(title: "无法读取图标", message: "请选择 PNG、JPG、ICO 或 ICNS 图片。", window: window)
            return
        }
        guard let stored = FileIconResolver.storeCustomIcon(image, for: ext) else {
            Dialog.alert(title: "保存失败", message: "无法保存图标文件，请重试。", window: window)
            return
        }
        if category == 2 && sender.tag >= FileIconCatalog.builtinOtherCount {
            AppSettings.addCustomIconExtension(ext)
        }
        AppSettings.setFileIconOverride(ext, path: stored)
    }

    @objc private func resetIcon(_ sender: NSButton) {
        let exts = currentExtensions
        guard exts.indices.contains(sender.tag) else { return }
        AppSettings.setFileIconOverride(exts[sender.tag], path: nil)
    }

    @objc private func addCustomType() {
        let raw = Dialog.textInput(title: "添加自定义类型", message: "输入扩展名（不含点号），例如 PSD：",
                                   confirmTitle: "添加", window: window) ?? ""
        let ext = raw.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        guard !ext.isEmpty, ext.count <= 16,
              CharacterSet(charactersIn: ext).isSubset(of: .alphanumerics) else {
            Dialog.alert(title: "扩展名无效", message: "请使用 1~16 位字母或数字。", window: window)
            return
        }
        guard !FileIconCatalog.isKnown(ext) else {
            Dialog.alert(title: "该类型已存在", message: "「\(ext.uppercased())」已在现有分类中，请直接更换其图标。", window: window)
            return
        }
        guard let path = chooseIconFile(), let image = NSImage(contentsOf: URL(fileURLWithPath: path)) else { return }
        guard let stored = FileIconResolver.storeCustomIcon(image, for: ext) else {
            Dialog.alert(title: "保存失败", message: "无法保存图标文件，请重试。", window: window)
            return
        }
        AppSettings.addCustomIconExtension(ext)
        AppSettings.setFileIconOverride(ext, path: stored)
    }

    @objc private func removeCustomType(_ sender: NSButton) {
        let exts = currentExtensions
        guard exts.indices.contains(sender.tag),
              sender.tag >= FileIconCatalog.builtinOtherCount else { return }
        AppSettings.removeCustomIconExtension(exts[sender.tag])
    }

    @objc private func resetBuiltinIcons() {
        guard Dialog.confirm(title: "恢复内置图标",
                             message: "将清除所有自定义图标设置，恢复为图标库默认样式。自定义类型也会一并删除。",
                             confirmTitle: "恢复", window: window) else { return }
        AppSettings.resetFileIcons()
    }

    @objc private func applyToSystem() {
        FileIconSystemApply.apply(clear: false, window: window)
    }

    @objc private func clearSystemIcons() {
        FileIconSystemApply.apply(clear: true, window: window)
    }

    private func chooseIconFile() -> String? {
        let panel = NSOpenPanel()
        panel.title = "选择图标文件"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ([.png, .jpeg, .icns, .tiff, .gif]
                                     + [UTType("com.microsoft.ico"), UTType("public.heic")].compactMap { $0 })
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    init() { super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class IconCell: NSView {
    let imageView = NSImageView(frame: NSRect(x: 8, y: 30, width: 42, height: 42))
    let nameLabel = NSTextField(labelWithString: "")
    let changeButton = NSButton(title: "更换", target: nil, action: nil)
    let resetButton = NSButton(title: "还原", target: nil, action: nil)
    var ext: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)

        nameLabel.frame = NSRect(x: 58, y: 50, width: 54, height: 18)
        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        nameLabel.alignment = .left
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        changeButton.frame = NSRect(x: 56, y: 26, width: 54, height: 22)
        changeButton.bezelStyle = .rounded
        changeButton.font = NSFont.systemFont(ofSize: 10)
        addSubview(changeButton)

        resetButton.frame = NSRect(x: 56, y: 4, width: 54, height: 22)
        resetButton.bezelStyle = .rounded
        resetButton.font = NSFont.systemFont(ofSize: 10)
        addSubview(resetButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
