import AppKit

/// XSpace 7-Zip 弹窗在 Dock 中的独立图标进程。
/// 它本身不承载窗口，只在弹窗存在期间显示一个 7-Zip Dock 图标；
/// 点击该图标时通知主 App 把对应的 7-Zip 窗口置前。
private let closeNotification = Notification.Name("XSpaceSevenZipDockClose")

private final class DockDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 用 7-Zip 图标替换默认的助手图标
        if let url = Bundle.main.url(forResource: "SevenZipDock", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 128, height: 128)
            NSApp.applicationIconImage = image
        }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(closeHelper(_:)),
            name: closeNotification,
            object: nil
        )
        // 主 App 异常退出时也要收起图标，避免留下孤立的 7-Zip Dock 图标
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            let mainAlive = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == "com.workbuddy.xspace"
            }
            if !mainAlive { NSApp.terminate(nil) }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func closeHelper(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock 图标被点击：写标记文件，主 App 的定时器会聚焦当前 7-Zip 窗口。
        // 用文件而不是 DistributedNotification，是因为弹窗的模态循环收不到通知。
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("xspace-sevenzip-focus.request")
        try? Date().timeIntervalSince1970.description.write(
            to: marker, atomically: true, encoding: .utf8
        )
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

let app = NSApplication.shared
private let delegate = DockDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
