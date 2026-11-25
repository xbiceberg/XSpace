import Foundation
import AppKit

// MARK: - 7-Zip 开源版核心封装
// 工具：7-Zip 25.01 (https://www.7-zip.org) 源码编译的 arm64 命令行版 7zz
// 格式能力：可创建 7z / ZIP / TAR / GZ / BZ2 / XZ；可解压 RAR / RAR5 / ISO / CAB 等
// 注意：RAR 为专有格式，开源版 7-Zip 只能解压，无法创建 RAR 压缩包。

enum SevenZip {
    /// 压缩包浏览窗口拖出的条目带这个标记，XSpace 主窗口据此强制“复制”而非“移动”，
    /// 避免把浏览用的临时文件搬走后无法继续拖放。
    static let archiveDragMarker = NSPasteboard.PasteboardType("com.xspace.archivebrowser.drag")

    static let supportedExtensions: Set<String> = [
        "7z", "zip", "zipx", "rar", "tar", "gz", "tgz", "bz2", "tbz2",
        "xz", "txz", "zst", "iso", "cab", "arj", "lzh", "lha", "z", "wim",
        "vhd", "vhdx", "vmdk", "mbr", "dmg", "cpio", "deb", "rpm", "xar", "chm"
    ]

    static var toolURL: URL? {
        Bundle.main.url(forResource: "7zz", withExtension: nil)
            ?? Bundle.main.url(forResource: "7zz", withExtension: "")
    }

    static func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if supportedExtensions.contains(ext) { return true }
        let lower = url.lastPathComponent.lowercased()
        return ["tar.gz", "tar.bz2", "tar.xz"].contains { lower.hasSuffix($0) }
    }

    struct RunResult {
        let stdout: String
        let stderr: String
        let code: Int32
        var ok: Bool { code == 0 }
    }

    @discardableResult
    static func run(_ args: [String]) -> RunResult {
        guard let tool = toolURL, FileManager.default.isExecutableFile(atPath: tool.path) else {
            return RunResult(stdout: "", stderr: "找不到 7zz 工具", code: -1)
        }
        let process = Process()
        process.executableURL = tool
        process.arguments = args
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return RunResult(stdout: "", stderr: error.localizedDescription, code: -1)
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return RunResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            code: process.terminationStatus
        )
    }

    // MARK: - 列出压缩包内容

    struct Entry {
        let path: String
        let isDirectory: Bool
        let size: Int64
        let modified: String

        var displayName: String { (path as NSString).lastPathComponent }
    }

    static func list(_ archive: URL, password: String = "") -> [Entry] {
        var args = ["l", "-slt", "-y"]
        if !password.isEmpty { args.append("-p\(password)") }
        args.append(archive.path)
        let output = run(args).stdout
        var entries: [Entry] = []
        var fields: [String: String] = [:]

        func flush() {
            guard let path = fields["Path"], path != "--", !path.isEmpty else {
                fields.removeAll(); return
            }
            entries.append(Entry(
                path: path,
                isDirectory: fields["Folder"] == "+",
                size: Int64(fields["Size"] ?? "") ?? 0,
                modified: fields["Modified"] ?? ""
            ))
            fields.removeAll()
        }

        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                if !fields.isEmpty { flush() }
                continue
            }
            if line.hasPrefix("Path = ") {
                if !fields.isEmpty { flush() }
                fields["Path"] = String(line.dropFirst("Path = ".count))
            } else if let sep = line.range(of: " = ") {
                fields[String(line[..<sep.lowerBound])] = String(line[sep.upperBound...])
            }
        }
        if !fields.isEmpty { flush() }
        return entries
    }

    // MARK: - 压缩

    struct CompressOptions {
        var format: String = "7z"          // 7z / zip / tar
        var level: Int = 5                 // 0..9
        var dictionaryMB: Int = 32
        var volumeMB: Int = 0              // 0 = 不分卷
        var password: String = ""
        var deleteSource: Bool = false

        var fileExtension: String {
            switch format {
            case "zip": return "zip"
            case "tar": return "tar"
            default: return "7z"
            }
        }
    }

    static func compress(_ urls: [URL], to archive: URL, options: CompressOptions) -> RunResult {
        guard !urls.isEmpty else { return RunResult(stdout: "", stderr: "没有要压缩的文件", code: -1) }
        var args: [String] = ["a", "-t\(options.format)", "-y", "-mx=\(options.level)"]
        // ZIP 格式不支持自定义字典参数
        if options.format == "7z", options.dictionaryMB > 0 {
            args.append("-md=\(options.dictionaryMB)m")
        }
        if options.volumeMB > 0 { args.append("-v\(options.volumeMB)m") }
        if !options.password.isEmpty { args.append("-p\(options.password)") }
        args.append(archive.path)
        args.append(contentsOf: urls.map(\.path))
        let result = run(args)
        if result.ok && options.deleteSource {
            for url in urls { try? FileManager.default.removeItem(at: url) }
        }
        return result
    }

    /// 默认参数压缩：在当前浏览目录生成 `当前目录名.<ext>`
    static func defaultArchiveURL(in directory: URL, ext: String = "7z") -> URL {
        let base = directory.lastPathComponent.isEmpty ? "Archive" : directory.lastPathComponent
        return uniqueURL(for: directory.appendingPathComponent("\(base).\(ext)"))
    }

    private static func uniqueURL(for url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) { return url }
        let ext = url.pathExtension
        let base = (url.lastPathComponent as NSString).deletingPathExtension
        var i = 2
        while true {
            let name = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    // MARK: - 解压

    static func extract(_ archive: URL, to directory: URL, password: String = "", paths: [String]? = nil) -> RunResult {
        var args: [String] = ["x", "-y", "-o\(directory.path)"]
        if !password.isEmpty { args.append("-p\(password)") }
        if let paths, !paths.isEmpty {
            for path in paths { args.append("-i!\(path)") }
        }
        args.append(archive.path)
        return run(args)
    }

    /// 解压整个压缩包到临时目录（用于浏览窗口）
    static func extractToTemporary(_ archive: URL, password: String = "") -> URL? {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("XSpace-7z-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let result = extract(archive, to: temp, password: password)
        if result.ok { return temp }
        try? FileManager.default.removeItem(at: temp)
        return nil
    }

    /// 仅解压指定条目到临时目录，返回解压出的真实路径（供双击打开 / 拖放使用）
    static func extractItem(_ archive: URL, path: String, password: String = "") -> URL? {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("XSpace-7z-view", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let session = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let result = extract(archive, to: session, password: password, paths: [path])
        guard result.ok else { return nil }
        return session.appendingPathComponent(path)
    }
}
