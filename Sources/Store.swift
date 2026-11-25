import Foundation
import AppKit

/// 可录制的快捷键（按键码 + 修饰键），用于截图等功能
struct KeyShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt
    var keyTitle: String

    static let defaultScreenshot = KeyShortcut(
        keyCode: 1, // 美式键盘 S
        modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue,
        keyTitle: "S"
    )

    /// 撤销默认 ⌘Z
    static let defaultUndo = KeyShortcut(
        keyCode: 6, // 美式键盘 Z
        modifiers: NSEvent.ModifierFlags.command.rawValue,
        keyTitle: "Z"
    )

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// 菜单里可用的 keyEquivalent（单字符按键；功能键交给键盘监听处理）
    var menuKey: String { keyTitle.count == 1 ? keyTitle.lowercased() : "" }

    func conflicts(with other: KeyShortcut) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    var displayString: String {
        var parts: [String] = []
        let flags = self.flags
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyTitle)
        return parts.joined()
    }
}

/// 「快速访问」里的一项：可排序、可增删，随设置持久化
struct QuickAccessItem: Codable, Equatable {
    var title: String
    var path: String
    var icon: String

    var url: URL { URL(fileURLWithPath: path) }
}

/// “修饰键 + 滚轮调整图标大小”中可使用的修饰键
enum IconResizeModifier: String, CaseIterable {
    case control
    case option
    case shift
    case command
    case function

    var title: String {
        switch self {
        case .control: return "Control (⌃)"
        case .option: return "Option (⌥)"
        case .shift: return "Shift (⇧)"
        case .command: return "Command (⌘)"
        case .function: return "Fn"
        }
    }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .control: return .control
        case .option: return .option
        case .shift: return .shift
        case .command: return .command
        case .function: return .function
        }
    }

    var index: Int { IconResizeModifier.allCases.firstIndex(of: self) ?? 0 }

    static func at(_ index: Int) -> IconResizeModifier {
        allCases.indices.contains(index) ? allCases[index] : .control
    }
}

/// 右键菜单中可自定义的菜单项；声明顺序即偏好设置右侧「可用功能」列表的展示顺序。
/// 「恢复默认」使用的顺序见 AppSettings.defaultContextMenuItems。
enum ContextMenuItemID: String, CaseIterable {
    // 默认菜单顺序，与用户截图一致：
    // 打开组 → 重命名/剪切/复制/粘贴 → 移到废纸篓/直接删除 → 显示简介 →（空白处）新建文件夹/刷新
    case open
    case openAlways
    case openInTerminal
    case separatorAfterOpen
    case rename
    case cut
    case copy
    case paste
    // 以下两个分隔符沿用旧的 rawValue，分别位于「粘贴」之后和「直接删除」之后
    case separatorAfterHash
    case trash
    case deletePermanently
    case separatorAfterRename
    case showInfo
    // 以下只在空白处右键出现
    case newFolder
    case refresh
    // 默认不在菜单里，可在偏好设置中自行添加（保留旧值以兼容已存设置）
    case openInOtherPane
    case openInNewWindow
    case computeHash
    case separatorAfterPaste
    case separatorBeforeRefresh
    case copyPath
    case revealInFinder
    /// 7-Zip 子菜单（压缩包显示解压组，其余显示压缩组）
    case sevenZip

    var title: String {
        switch self {
        case .open: return "打开"
        case .openAlways: return "始终以此方式打开"
        case .openInOtherPane: return "在新窗格中打开"
        case .openInNewWindow: return "新窗口打开"
        case .openInTerminal: return "在终端打开"
        case .separatorAfterOpen, .separatorAfterHash, .separatorAfterRename,
             .separatorAfterPaste, .separatorBeforeRefresh: return "—— 分割线 ——"
        case .newFolder: return "新建文件夹"
        case .deletePermanently: return "直接删除"
        case .computeHash: return "计算哈希值"
        case .rename: return "重命名"
        case .cut: return "剪切"
        case .copy: return "复制"
        case .paste: return "粘贴到此处"
        case .trash: return "移到废纸篓"
        case .copyPath: return "拷贝路径"
        case .revealInFinder: return "在访达中显示"
        case .showInfo: return "显示简介"
        case .refresh: return "刷新"
        case .sevenZip: return "7-Zip"
        }
    }

    var isSeparator: Bool { title.hasPrefix("——") }
}

/// 主窗口的窗格布局（1~4 个窗格）
enum PaneLayout: String, CaseIterable {
    case single          // 单窗口
    case twoRows         // 双窗口（上下）
    case twoColumns      // 双窗口（左右）
    case threeLeftOne    // 三窗口（左一右二）
    case threeLeftTwo    // 三窗口（左二右一）
    case four            // 四窗口

    /// 最多支持的窗格数
    static let maxPanes = 4

    var paneCount: Int {
        switch self {
        case .single: return 1
        case .twoRows, .twoColumns: return 2
        case .threeLeftOne, .threeLeftTwo: return 3
        case .four: return 4
        }
    }

    var title: String {
        switch self {
        case .single: return "单窗口"
        case .twoRows: return "双窗口（上下）"
        case .twoColumns: return "双窗口（左右）"
        case .threeLeftOne: return "三窗口（左一右二）"
        case .threeLeftTwo: return "三窗口（左二右一）"
        case .four: return "四窗口"
        }
    }

    var index: Int { PaneLayout.allCases.firstIndex(of: self) ?? 0 }

    static func at(_ index: Int) -> PaneLayout {
        allCases.indices.contains(index) ? allCases[index] : .threeLeftOne
    }
}

struct WorkspaceSnapshot: Codable {
    let name: String
    let paths: [String]
}

enum WallpaperFillMode: String, CaseIterable {
    case stretch
    case tile
    case center
    case fill

    var title: String {
        switch self {
        case .stretch: return "拉伸"
        case .tile: return "平铺"
        case .center: return "居中"
        case .fill: return "填充"
        }
    }

    static func mode(at index: Int) -> WallpaperFillMode {
        let modes = WallpaperFillMode.allCases
        guard modes.indices.contains(index) else { return .stretch }
        return modes[index]
    }

    var index: Int { WallpaperFillMode.allCases.firstIndex(of: self) ?? 0 }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard
    private static let paneKey = "qspacelite.panes"
    private static let defaultPathsKey = "qspacelite.defaultPaths"
    private static let bookmarksKey = "qspacelite.bookmarks"
    private static let quickAccessKey = "qspacelite.quickAccess"
    private static let legacyCustomPathsKey = "qspacelite.customPaths"   // 旧版只存自定义路径，仅用于迁移
    private static let workspacesKey = "qspacelite.workspaces"
    private static let hiddenKey = "qspacelite.showHiddenFiles"
    private static let sidebarKey = "qspacelite.sidebarVisible"
    private static let confirmTrashKey = "qspacelite.confirmTrash"
    private static let confirmDeleteKey = "qspacelite.confirmDelete"
    private static let modesKey = "qspacelite.viewModes"
    private static let sortsKey = "qspacelite.sortKeys"
    private static let iconSizesKey = "qspacelite.iconSizes"
    private static let textSizesKey = "qspacelite.textSizes"
    private static let iconResizeModifierKey = "qspacelite.iconResizeModifier"
    private static let screenshotShortcutKey = "qspacelite.screenshotShortcut"
    private static let undoShortcutKey = "qspacelite.undoShortcut"
    private static let undoLimitKey = "qspacelite.undoLimit"
    private static let screenshotDirectoryKey = "qspacelite.screenshotDirectory"
    private static let globalWallpaperKey = "qspacelite.globalWallpaper"
    private static let globalWallpaperDisabledKey = "qspacelite.globalWallpaperDisabled"
    private static let globalBlurKey = "qspacelite.globalBlur"
    private static let paneWallpapersKey = "qspacelite.paneWallpapers"
    private static let paneBlursKey = "qspacelite.paneBlurs"
    private static let globalWallpaperModeKey = "qspacelite.globalWallpaperMode"
    private static let paneWallpaperModesKey = "qspacelite.paneWallpaperModes"
    private static let contextMenuItemsKey = "qspacelite.contextMenuItems"
    private static let paneLayoutKey = "qspacelite.paneLayout"
    private static let contextMenuMigratedKey = "qspacelite.contextMenuMigratedNewWindow"
    private static let contextMenuMigratedSevenZipKey = "qspacelite.contextMenuMigratedSevenZip"
    private static let sevenZipFormatKey = "qspacelite.sevenZipFormat"
    private static let sevenZipLevelKey = "qspacelite.sevenZipLevel"

    static var defaultPaneURLs: [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Documents")
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Downloads")
        // 窗格 1 文稿 / 窗格 2 根目录 / 窗格 3 下载 / 窗格 4 个人
        return [documents, URL(fileURLWithPath: "/"), downloads, home]
    }

    /// 按需要的窗格数量返回对应目录；未保存或目录已失效时回退到默认路径
    static func paneURLs(count: Int) -> [URL] {
        let fallback = defaultPaths()
        let saved = defaults.stringArray(forKey: paneKey) ?? []
        return (0..<max(0, count)).map { index in
            if let raw = saved[safe: index], !raw.isEmpty {
                let url = URL(fileURLWithPath: raw)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return url
                }
            }
            return fallback[safe: index] ?? FileManager.default.homeDirectoryForCurrentUser
        }
    }

    /// 每个窗格用户设定的默认路径；未设置时回退到内置默认目录
    static func defaultPaths() -> [URL] {
        let base = defaultPaneURLs
        guard let strings = defaults.stringArray(forKey: defaultPathsKey) else { return base }
        return base.enumerated().map { index, fallback in
            guard let raw = strings[safe: index] else { return fallback }
            let url = URL(fileURLWithPath: raw)
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
                ? url
                : fallback
        }
    }

    static func setDefaultPath(_ url: URL, for index: Int) {
        guard index >= 0, index < PaneLayout.maxPanes else { return }
        var paths = defaultPaths()
        paths[index] = url
        defaults.set(paths.map(\.path), forKey: defaultPathsKey)
    }

    static func resetDefaultPaths() {
        defaults.removeObject(forKey: defaultPathsKey)
    }

    /// 只更新前 N 个窗格，保留其余已保存路径，切换布局时不丢目录
    static func savePaneURLs(_ urls: [URL]) {
        var saved = defaults.stringArray(forKey: paneKey) ?? []
        while saved.count < urls.count { saved.append("") }
        for (index, url) in urls.enumerated() { saved[index] = url.path }
        defaults.set(saved, forKey: paneKey)
    }

    static var bookmarks: [URL] {
        get {
            (defaults.stringArray(forKey: bookmarksKey) ?? []).map { URL(fileURLWithPath: $0) }.filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
        }
        set { defaults.set(newValue.map(\.path), forKey: bookmarksKey) }
    }

    // MARK: - 快速访问

    /// 内置默认的「快速访问」条目
    static var defaultQuickAccessItems: [QuickAccessItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        func dir(_ kind: FileManager.SearchPathDirectory, _ fallback: String) -> String {
            fm.urls(for: kind, in: .userDomainMask).first?.path ?? home.appendingPathComponent(fallback).path
        }
        return [
            QuickAccessItem(title: "个人", path: home.path, icon: "house"),
            QuickAccessItem(title: "桌面", path: dir(.desktopDirectory, "Desktop"), icon: "rectangle.on.rectangle"),
            QuickAccessItem(title: "文稿", path: dir(.documentDirectory, "Documents"), icon: "doc.text.fill"),
            QuickAccessItem(title: "下载", path: dir(.downloadsDirectory, "Downloads"), icon: "arrow.down.circle"),
            QuickAccessItem(title: "图片", path: dir(.picturesDirectory, "Pictures"), icon: "photo"),
            QuickAccessItem(title: "应用程序", path: "/Applications", icon: "app.dashed")
        ]
    }

    /// 侧边栏「快速访问」的完整列表（顺序即显示顺序）
    static var quickAccessItems: [QuickAccessItem] {
        get {
            if let data = defaults.data(forKey: quickAccessKey),
               let items = try? JSONDecoder().decode([QuickAccessItem].self, from: data) {
                return items
            }
            // 首次运行：默认项 + 把旧版“自定义路径”迁移进列表
            var items = defaultQuickAccessItems
            for raw in defaults.stringArray(forKey: legacyCustomPathsKey) ?? [] {
                let url = URL(fileURLWithPath: raw).standardizedFileURL
                guard !items.contains(where: { $0.path == url.path }) else { continue }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }
                items.append(QuickAccessItem(title: url.lastPathComponent, path: url.path, icon: "folder"))
            }
            return items
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: quickAccessKey)
            }
            NotificationCenter.default.post(name: .xspaceCustomPathsChanged, object: nil)
        }
    }

    static func removeQuickAccess(path: String) {
        var items = quickAccessItems
        items.removeAll { $0.path == path }
        quickAccessItems = items
    }

    static var workspaces: [WorkspaceSnapshot] {
        get {
            guard let data = defaults.data(forKey: workspacesKey) else { return [] }
            return (try? JSONDecoder().decode([WorkspaceSnapshot].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: workspacesKey)
        }
    }

    static var showHiddenFiles: Bool {
        get { defaults.bool(forKey: hiddenKey) }
        set { defaults.set(newValue, forKey: hiddenKey) }
    }

    static var sidebarVisible: Bool {
        get { defaults.object(forKey: sidebarKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: sidebarKey) }
    }

    /// 主窗口的窗格布局，默认保持原来的「三窗口（左一右二）」
    static var paneLayout: PaneLayout {
        get { PaneLayout(rawValue: defaults.string(forKey: paneLayoutKey) ?? "") ?? .threeLeftOne }
        set { defaults.set(newValue.rawValue, forKey: paneLayoutKey) }
    }

    /// 移到废纸篓前是否弹窗确认，默认关闭（右键直接移到废纸篓）
    static var confirmBeforeTrash: Bool {
        get { defaults.object(forKey: confirmTrashKey) as? Bool ?? false }
        set { defaults.set(newValue, forKey: confirmTrashKey) }
    }

    /// 永久删除前是否弹窗确认，默认开启（此操作不可恢复）
    static var confirmBeforeDelete: Bool {
        get { defaults.object(forKey: confirmDeleteKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: confirmDeleteKey) }
    }

    static func viewModes() -> [PaneViewMode] {
        let raw = defaults.stringArray(forKey: modesKey) ?? []
        return (0..<PaneLayout.maxPanes).map { index in
            if let value = raw[safe: index], let mode = PaneViewMode(rawValue: value) { return mode }
            return index == 2 ? .list : .icon
        }
    }

    static func saveViewModes(_ modes: [PaneViewMode]) {
        var saved = defaults.stringArray(forKey: modesKey) ?? []
        while saved.count < modes.count { saved.append("") }
        for (index, mode) in modes.enumerated() { saved[index] = mode.rawValue }
        defaults.set(saved, forKey: modesKey)
    }

    static func sortKeys() -> [PaneSortKey] {
        let raw = defaults.stringArray(forKey: sortsKey) ?? []
        return (0..<PaneLayout.maxPanes).map { index in
            PaneSortKey(rawValue: raw[safe: index] ?? "") ?? .name
        }
    }

    static func saveSortKeys(_ keys: [PaneSortKey]) {
        var saved = defaults.stringArray(forKey: sortsKey) ?? []
        while saved.count < keys.count { saved.append("") }
        for (index, key) in keys.enumerated() { saved[index] = key.rawValue }
        defaults.set(saved, forKey: sortsKey)
    }

    // MARK: - 外观：每个窗格的图标与文字大小

    static func iconSize(for index: Int) -> CGFloat {
        let values = defaults.array(forKey: iconSizesKey) as? [Double] ?? [64, 64, 64]
        return CGFloat(values[safe: index] ?? 64)
    }

    static func setIconSize(_ size: CGFloat, for index: Int) {
        var values = (defaults.array(forKey: iconSizesKey) as? [Double] ?? [64, 64, 64])
        while values.count < PaneLayout.maxPanes { values.append(64) }
        guard values.indices.contains(index) else { return }
        values[index] = Double(size)
        defaults.set(values, forKey: iconSizesKey)
    }

    static func textSize(for index: Int) -> CGFloat {
        let values = defaults.array(forKey: textSizesKey) as? [Double] ?? [12, 12, 12]
        return CGFloat(values[safe: index] ?? 12)
    }

    static func setTextSize(_ size: CGFloat, for index: Int) {
        var values = (defaults.array(forKey: textSizesKey) as? [Double] ?? [12, 12, 12])
        while values.count < PaneLayout.maxPanes { values.append(12) }
        guard values.indices.contains(index) else { return }
        values[index] = Double(size)
        defaults.set(values, forKey: textSizesKey)
    }

    /// 滚轮调整图标大小时使用的修饰键，默认为 Control
    static var iconResizeModifier: IconResizeModifier {
        get { IconResizeModifier(rawValue: defaults.string(forKey: iconResizeModifierKey) ?? "") ?? .control }
        set { defaults.set(newValue.rawValue, forKey: iconResizeModifierKey) }
    }

    /// 截图快捷键，默认 ⇧⌘S
    static var screenshotShortcut: KeyShortcut {
        get {
            guard let data = defaults.data(forKey: screenshotShortcutKey),
                  let shortcut = try? JSONDecoder().decode(KeyShortcut.self, from: data) else {
                return .defaultScreenshot
            }
            return shortcut
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: screenshotShortcutKey)
            }
            NotificationCenter.default.post(name: .xspaceShortcutChanged, object: nil)
        }
    }

    /// 撤销快捷键，默认 ⌘Z
    static var undoShortcut: KeyShortcut {
        get {
            guard let data = defaults.data(forKey: undoShortcutKey),
                  let shortcut = try? JSONDecoder().decode(KeyShortcut.self, from: data) else {
                return .defaultUndo
            }
            return shortcut
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: undoShortcutKey)
            }
            NotificationCenter.default.post(name: .xspaceUndoSettingsChanged, object: nil)
        }
    }

    /// 撤销栈保留的最大步数，默认 5，范围 1~20
    static var undoLimit: Int {
        get {
            guard defaults.object(forKey: undoLimitKey) != nil else { return 5 }
            return min(20, max(1, defaults.integer(forKey: undoLimitKey)))
        }
        set {
            defaults.set(min(20, max(1, newValue)), forKey: undoLimitKey)
            NotificationCenter.default.post(name: .xspaceUndoSettingsChanged, object: nil)
        }
    }

    // MARK: - 截图保存目录

    /// 默认保存到「文稿」
    static var defaultScreenshotDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
    }

    /// 截图存放目录；未设置时使用「文稿」
    static var screenshotDirectory: URL {
        get {
            guard let path = defaults.string(forKey: screenshotDirectoryKey), !path.isEmpty else {
                return defaultScreenshotDirectory
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            let standardized = newValue.standardizedFileURL
            if standardized.path == defaultScreenshotDirectory.standardizedFileURL.path {
                defaults.removeObject(forKey: screenshotDirectoryKey)
            } else {
                defaults.set(standardized.path, forKey: screenshotDirectoryKey)
            }
        }
    }

    static var isUsingDefaultScreenshotDirectory: Bool {
        (defaults.string(forKey: screenshotDirectoryKey) ?? "").isEmpty
    }

    // MARK: - 壁纸

    /// 内置默认壁纸（打包在 App 的 Resources 里），随软件一起分发
    static var bundledWallpaperPath: String? {
        Bundle.main.url(forResource: "default-wallpaper", withExtension: "jpg")?.path
    }

    /// 全局壁纸：用户没选过时使用内置星空图；点「清除」后不再回退到内置图
    static var globalWallpaperPath: String? {
        get {
            if defaults.bool(forKey: globalWallpaperDisabledKey) { return nil }
            if let path = defaults.string(forKey: globalWallpaperKey) { return path }
            return bundledWallpaperPath
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: globalWallpaperKey)
                defaults.set(false, forKey: globalWallpaperDisabledKey)
            } else {
                defaults.removeObject(forKey: globalWallpaperKey)
                defaults.set(true, forKey: globalWallpaperDisabledKey)
            }
        }
    }

    static var globalWallpaperBlur: Int {
        get { defaults.object(forKey: globalBlurKey) as? Int ?? 100 }
        set { defaults.set(newValue, forKey: globalBlurKey) }
    }

    static func paneWallpaperPath(for index: Int) -> String? {
        let values = defaults.stringArray(forKey: paneWallpapersKey) ?? ["", "", ""]
        let value = values[safe: index] ?? ""
        return value.isEmpty ? nil : value
    }

    static func setPaneWallpaperPath(_ path: String?, for index: Int) {
        var values = defaults.stringArray(forKey: paneWallpapersKey) ?? ["", "", ""]
        while values.count < PaneLayout.maxPanes { values.append("") }
        guard values.indices.contains(index) else { return }
        values[index] = path ?? ""
        defaults.set(values, forKey: paneWallpapersKey)
    }

    static func paneWallpaperBlur(for index: Int) -> Int {
        let values = defaults.array(forKey: paneBlursKey) as? [Int] ?? [20, 20, 20]
        return values[safe: index] ?? 20
    }

    static func setPaneWallpaperBlur(_ blur: Int, for index: Int) {
        var values = defaults.array(forKey: paneBlursKey) as? [Int] ?? [20, 20, 20]
        while values.count < PaneLayout.maxPanes { values.append(20) }
        guard values.indices.contains(index) else { return }
        values[index] = blur
        defaults.set(values, forKey: paneBlursKey)
    }

    // MARK: - 壁纸填充模式

    static var globalWallpaperMode: WallpaperFillMode {
        get { WallpaperFillMode(rawValue: defaults.string(forKey: globalWallpaperModeKey) ?? "") ?? .stretch }
        set { defaults.set(newValue.rawValue, forKey: globalWallpaperModeKey) }
    }

    static func paneWallpaperMode(for index: Int) -> WallpaperFillMode {
        let values = defaults.stringArray(forKey: paneWallpaperModesKey) ?? ["stretch", "stretch", "stretch"]
        return WallpaperFillMode(rawValue: values[safe: index] ?? "") ?? .stretch
    }

    static func setPaneWallpaperMode(_ mode: WallpaperFillMode, for index: Int) {
        var values = defaults.stringArray(forKey: paneWallpaperModesKey) ?? ["stretch", "stretch", "stretch"]
        while values.count < PaneLayout.maxPanes { values.append("stretch") }
        guard values.indices.contains(index) else { return }
        values[index] = mode.rawValue
        defaults.set(values, forKey: paneWallpaperModesKey)
    }

    // MARK: - 右键菜单自定义

    /// 默认右键菜单顺序（2026-11-25 按用户设置页截图调整）：
    /// 打开 / 始终以此方式打开 / 新窗口打开 / 分割线 /
    /// 重命名 / 剪切 / 复制 / 粘贴到此处 / 分割线 /
    /// 移到废纸篓 / 直接删除 / 在终端打开 / 7-Zip / 分割线 /
    /// 新建文件夹 / 显示简介 / 刷新
    /// 未包含「在新窗格中打开 / 计算哈希值 / 拷贝路径 / 在访达中显示」。
    /// 注意：分隔符只关心位置，rawValue 沿用旧值以兼容用户已保存的设置。
    static var defaultContextMenuItems: [ContextMenuItemID] {
        [.open, .openAlways, .openInNewWindow, .separatorAfterOpen,
         .rename, .cut, .copy, .paste, .separatorAfterHash,
         .trash, .deletePermanently, .openInTerminal, .sevenZip, .separatorAfterRename,
         .newFolder, .showInfo, .refresh]
    }

    /// 当前启用的右键菜单项（含顺序）；未配置时使用默认项
    static var contextMenuItems: [ContextMenuItemID] {
        get {
            guard let raw = defaults.stringArray(forKey: contextMenuItemsKey) else {
                return defaultContextMenuItems
            }
            var items = raw.compactMap(ContextMenuItemID.init(rawValue:))
            guard !items.isEmpty else { return defaultContextMenuItems }
            // 一次性迁移：旧版本保存的菜单里没有「新窗口打开」，自动补到「打开」组之后
            if !defaults.bool(forKey: contextMenuMigratedKey) {
                if !items.contains(.openInNewWindow) {
                    let anchor = items.firstIndex(of: .openAlways) ?? items.firstIndex(of: .open)
                    items.insert(.openInNewWindow, at: (anchor.map { $0 + 1 }) ?? items.count)
                    defaults.set(items.map(\.rawValue), forKey: contextMenuItemsKey)
                }
                defaults.set(true, forKey: contextMenuMigratedKey)
            }
            // 一次性迁移：7-Zip 现在是可自定义的菜单项，老配置补到末尾（保持原先固定在末尾的效果）
            if !defaults.bool(forKey: contextMenuMigratedSevenZipKey) {
                if !items.contains(.sevenZip) {
                    items.append(.sevenZip)
                    defaults.set(items.map(\.rawValue), forKey: contextMenuItemsKey)
                }
                defaults.set(true, forKey: contextMenuMigratedSevenZipKey)
            }
            return items
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: contextMenuItemsKey) }
    }

    static func resetContextMenuItems() {
        defaults.removeObject(forKey: contextMenuItemsKey)
    }

    // MARK: - 7-ZIP 设置

    /// 默认压缩格式：7z / zip / tar
    static var sevenZipFormat: String {
        get {
            let value = defaults.string(forKey: sevenZipFormatKey)?.lowercased() ?? "7z"
            return ["7z", "zip", "tar"].contains(value) ? value : "7z"
        }
        set { defaults.set(newValue.lowercased(), forKey: sevenZipFormatKey) }
    }

    /// 默认压缩级别：0~9，默认 5（标准）
    static var sevenZipLevel: Int {
        get {
            guard defaults.object(forKey: sevenZipLevelKey) != nil else { return 5 }
            return min(9, max(0, defaults.integer(forKey: sevenZipLevelKey)))
        }
        set { defaults.set(min(9, max(0, newValue)), forKey: sevenZipLevelKey) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}

extension Notification.Name {
    static let xspaceAppearanceChanged = Notification.Name("xspace.appearanceChanged")
    static let xspaceCustomPathsChanged = Notification.Name("xspace.customPathsChanged")
    static let xspaceShortcutChanged = Notification.Name("xspace.shortcutChanged")
    static let xspaceScreenshotSaved = Notification.Name("xspace.screenshotSaved")
    static let xspaceLayoutChanged = Notification.Name("xspace.layoutChanged")
    static let xspaceUndoStackChanged = Notification.Name("xspace.undoStackChanged")
    static let xspaceUndoSettingsChanged = Notification.Name("xspace.undoSettingsChanged")
}
