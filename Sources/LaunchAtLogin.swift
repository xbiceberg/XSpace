import Foundation
import Darwin

/// 开机自启动：通过用户级 LaunchAgent 在登录后自动运行 XSpace。
/// 直接启动已安装 App 的可执行文件并带 `--launch-background` 参数，
/// 保证登录后完全隐藏到后台、不在 Dock 最小化区留下窗口缩略图。
enum LaunchAtLogin {
    static let label = "com.workbuddy.xspace.startup"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// 返回操作是否成功。开关变化时立即生效，无需注销重登。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            let appPath = "/Applications/XSpace.app"
            guard FileManager.default.fileExists(atPath: appPath) else { return false }
            let plist: [String: Any] = [
                "Label": label,
                // 直接启动二进制并传标记：`open -a` 会激活 App，导致刚最小化的窗口被重新显示
                "ProgramArguments": [appPath + "/Contents/MacOS/XSpace", "--launch-background"],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive"
            ]
            do {
                try FileManager.default.createDirectory(
                    at: plistURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try (plist as NSDictionary).write(to: plistURL)
            } catch {
                return false
            }
            runLaunchctl("bootstrap", "gui/\(getuid())", plistURL.path)
            runLaunchctl("enable", "gui/\(getuid())/\(label)")
            return true
        }

        runLaunchctl("bootout", "gui/\(getuid())/\(label)")
        do {
            try FileManager.default.removeItem(at: plistURL)
        } catch {
            return !FileManager.default.fileExists(atPath: plistURL.path)
        }
        return true
    }

    private static func runLaunchctl(_ arguments: String...) {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = arguments
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // 已加载/未加载时 launchctl 会返回非零，忽略即可。
        }
    }
}
