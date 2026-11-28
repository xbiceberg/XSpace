import Foundation

/// 目录 / .app bundle 的逻辑大小缓存。
///
/// 应用包一旦安装就很少改动，首次递归统计后把结果写入 plist，之后直接读缓存，
/// 避免每次列目录都遍历上千个文件（大型 App 可达数万个文件，实时计算会明显卡顿）。
enum DirectorySizeCache {
    private struct Entry: Codable {
        let size: Int64
        let fileCount: Int
    }

    private static let storeURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/XSpace/directory-sizes.plist")
    private static let queue = DispatchQueue(label: "com.workbuddy.xspace.dirsizecache", qos: .utility)
    private static var entries: [String: Entry] = load()

    private static func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? PropertyListDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func save() {
        guard let data = try? PropertyListEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: storeURL, options: .atomic)
    }

    /// 读取已缓存的大小；没有缓存返回 nil。
    static func cached(for url: URL) -> Int64? {
        queue.sync { entries[cacheKey(url)]?.size }
    }

    /// 同步返回大小：命中缓存直接用，否则递归计算并写入缓存。
    /// 调用方应确保在后台队列执行（首次计算可能遍历大量文件）。
    static func sizeSync(for url: URL) -> Int64 {
        let key = cacheKey(url)
        if let hit = queue.sync(execute: { entries[key] }) { return hit.size }
        let (size, count) = compute(url)
        queue.sync(execute: {
            entries[key] = Entry(size: size, fileCount: count)
            save()
        })
        return size
    }

    private static func cacheKey(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    private static func compute(_ url: URL) -> (Int64, Int) {
        let fm = FileManager.default
        let root = url.resolvingSymlinksInPath()
        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                             options: [.skipsHiddenFiles],
                                             errorHandler: nil) else { return (0, 0) }
        var total: Int64 = 0
        var count = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                  values.isDirectory != true else { continue }
            total += Int64(values.fileSize ?? 0)
            count += 1
        }
        return (total, count)
    }
}
