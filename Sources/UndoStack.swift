import AppKit

/// 类 Windows 资源管理器的文件操作撤销栈：只保存最近一系列可逆操作
final class FileUndoStack {
    static let shared = FileUndoStack()

    private struct Entry {
        let title: String
        let undo: () -> Void
    }

    private var entries: [Entry] = []
    private let lock = NSLock()

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(undoSettingsDidChange),
            name: .xspaceUndoSettingsChanged,
            object: nil
        )
    }

    @objc private func undoSettingsDidChange() { trimToLimit() }

    /// 只保留最近 N 条（N 由设置决定，默认 5，最多 20）
    private func trimToLimit() {
        lock.lock()
        let limit = AppSettings.undoLimit
        let trimmed = entries.count > limit
        if trimmed { entries = Array(entries.suffix(limit)) }
        lock.unlock()
        if trimmed { NotificationCenter.default.post(name: .xspaceUndoStackChanged, object: nil) }
    }

    func record(_ title: String, undo: @escaping () -> Void) {
        lock.lock()
        entries.append(Entry(title: title, undo: undo))
        let limit = AppSettings.undoLimit
        if entries.count > limit { entries = Array(entries.suffix(limit)) }
        lock.unlock()
        NotificationCenter.default.post(name: .xspaceUndoStackChanged, object: nil)
    }

    var canUndo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !entries.isEmpty
    }

    var lastTitle: String? {
        lock.lock()
        defer { lock.unlock() }
        return entries.last?.title
    }

    @discardableResult
    func undo() -> String? {
        lock.lock()
        guard let entry = entries.popLast() else {
            lock.unlock()
            return nil
        }
        lock.unlock()
        entry.undo()
        NotificationCenter.default.post(name: .xspaceUndoStackChanged, object: nil)
        return entry.title
    }

    func clear() {
        lock.lock()
        let had = !entries.isEmpty
        entries.removeAll()
        lock.unlock()
        if had { NotificationCenter.default.post(name: .xspaceUndoStackChanged, object: nil) }
    }
}

/// 撤销执行时的底层文件动作：失败才提示，不弹成功框
enum UndoIO {
    static func move(_ source: URL, to destination: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: source.path) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                let free = FileOperations.uniqueURL(for: destination)
                try FileManager.default.moveItem(at: source, to: free)
            } else {
                try FileManager.default.moveItem(at: source, to: destination)
            }
            return true
        } catch {
            Dialog.alert(title: "撤销失败", message: "\(source.lastPathComponent)：\(error.localizedDescription)")
            return false
        }
    }

    static func remove(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            Dialog.alert(title: "撤销失败", message: "\(url.lastPathComponent)：\(error.localizedDescription)")
            return false
        }
    }
}
