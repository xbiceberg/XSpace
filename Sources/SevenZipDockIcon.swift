import AppKit

/// 7-Zip 弹窗的独立 Dock 图标。
///
/// macOS 的 Dock 图标按进程显示，同一个 App 的多个窗口不会各自出现图标。
/// 因此在这里启动一个内嵌的小助手 App（SevenZipDock.app），只在 7-Zip
/// 压缩/解压面板或压缩包浏览窗口存在时显示一个 7-Zip 图标；点击该图标时
/// 通知主 App 把对应窗口置前，窗口关闭后助手自动退出。
final class SevenZipDockIcon {
    private static let closeName = Notification.Name("XSpaceSevenZipDockClose")
    private static let windows = NSHashTable<NSWindow>.weakObjects()
    private static var helperRunning = false
    private static var focusTimer: Timer?
    private static var lastFocusRequest: Date?

    /// 助手与宿主共用的聚焦标记（DistributedNotification 在模态循环里收不到）
    static var focusMarkerURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("xspace-sevenzip-focus.request")
    }

    /// 在主 App 启动时安装“聚焦 7-Zip 窗口”的轮询（.common 模式在模态弹窗期间也会触发）
    static func install() {
        guard focusTimer == nil else { return }
        try? FileManager.default.removeItem(at: focusMarkerURL)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            checkFocusRequest()
        }
        RunLoop.main.add(timer, forMode: .common)
        focusTimer = timer
    }

    private static func checkFocusRequest() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: focusMarkerURL.path),
              let date = attrs[.modificationDate] as? Date else { return }
        if let last = lastFocusRequest, date <= last { return }
        lastFocusRequest = date
        NSApp.activate(ignoringOtherApps: true)
        let candidates = windows.allObjects
        let window = candidates.first { !$0.isMiniaturized } ?? candidates.first
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// 一个 7-Zip 窗口出现：登记并（必要时）拉起 Dock 助手
    static func show(for window: NSWindow) {
        windows.add(window)
        guard !helperRunning,
              let helper = Bundle.main.url(forResource: "SevenZipDock", withExtension: "app")
        else { return }
        helperRunning = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(helper, configuration: configuration, completionHandler: nil)
    }

    /// 一个 7-Zip 窗口消失：没有剩余窗口时收起 Dock 图标
    static func hide(for window: NSWindow) {
        windows.remove(window)
        guard windows.count == 0, helperRunning else { return }
        helperRunning = false
        DistributedNotificationCenter.default().postNotificationName(
            closeName, object: nil, userInfo: nil, deliverImmediately: true
        )
    }
}
