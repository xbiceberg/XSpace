import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    /// 界面显示名称：应用程序包隐藏 .app 扩展名，例如“抖音.app”显示为“抖音”
    let displayName: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date?
    let kind: String
    let icon: NSImage
    /// 图片文件的真实缩略图（JPEG / PNG 等）；非图片文件为 nil
    let thumbnail: NSImage?

    var id: URL { url }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        // .app 虽然在系统里是目录（bundle），但在文件管理器中应作为“应用程序”而非文件夹处理
        let isAppBundle = url.pathExtension.lowercased() == "app"
        self.displayName = isAppBundle
            ? (self.name as NSString).deletingPathExtension
            : self.name
        self.isDirectory = isDir.boolValue && !isAppBundle

        var sizeValue: Int64 = 0
        var modifiedDate: Date?
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
            sizeValue = Int64(values.fileSize ?? 0)
            modifiedDate = values.contentModificationDate
        }
        self.size = sizeValue
        self.modified = modifiedDate

        if isAppBundle {
            // 应用程序包在系统里是目录，但在文件管理器中应显示为“应用程序”
            self.kind = "应用程序"
        } else if isDir.boolValue {
            self.kind = "文件夹"
        } else {
            var typeIdentifier: String?
            if let values = try? url.resourceValues(forKeys: [.typeIdentifierKey]) {
                typeIdentifier = values.typeIdentifier
            }
            let type = UTType(typeIdentifier ?? "") ?? UTType(filenameExtension: url.pathExtension) ?? .data
            self.kind = type.localizedDescription ?? "文件"
        }
        self.icon = IconCache.icon(for: url, isDirectory: self.isDirectory)
        self.thumbnail = IconCache.thumbnail(for: url)
    }
}

enum IconCache {
    private static var folderIcon: NSImage = NSWorkspace.shared.icon(for: .folder)
    private static var genericIcon: NSImage = NSWorkspace.shared.icon(for: .data)
    // 三个窗格会在后台队列并发创建 FileItem；NSCache 本身线程安全，
    // 普通 Swift Dictionary 并发写会导致 _NativeDictionary.setValue 崩溃。
    private static let extensionIcons = NSCache<NSString, NSImage>()
    private static let appIcons = NSCache<NSString, NSImage>()
    private static let thumbnailCache = NSCache<NSString, NSImage>()
    private static let thumbnailLock = NSLock()
    // NSWorkspace / ImageIO 的图标查找并非线程安全，串行化缓存未命中的创建过程
    private static let iconLock = NSLock()
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp"
    ]

    /// 为图片文件生成圆角缩略图：正方形画布内等比缩放显示完整图片，不裁剪
    static func thumbnail(for url: URL) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        guard imageExtensions.contains(ext) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(Int(modified))|fit" as NSString
        // lockFocus/unlockFocus 依赖 AppKit 图形上下文，后台线程并发绘制需要串行化
        thumbnailLock.lock()
        defer { thumbnailLock.unlock() }
        if let cached = thumbnailCache.object(forKey: key) { return cached }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let canvas = NSSize(width: 320, height: 320)
        let padding: CGFloat = 24
        let visible = NSRect(x: padding, y: padding,
                             width: canvas.width - padding * 2,
                             height: canvas.height - padding * 2)
        // aspect fit：整张图等比缩放到画布内，不裁掉任何内容
        let scale = min(visible.width / CGFloat(cgImage.width),
                        visible.height / CGFloat(cgImage.height))
        let drawWidth = CGFloat(cgImage.width) * scale
        let drawHeight = CGFloat(cgImage.height) * scale
        let target = NSRect(x: visible.midX - drawWidth / 2,
                            y: visible.midY - drawHeight / 2,
                            width: drawWidth,
                            height: drawHeight)
        let radius = min(14, min(target.width, target.height) / 8)
        let image = NSImage(size: canvas)
        image.lockFocus()
        let path = NSBezierPath(roundedRect: target, xRadius: radius, yRadius: radius)
        path.addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSBitmapImageRep(cgImage: cgImage).draw(in: target)
        NSColor.white.withAlphaComponent(0.22).setStroke()
        let border = NSBezierPath(roundedRect: target.insetBy(dx: 0.5, dy: 0.5),
                                  xRadius: max(0, radius - 0.5),
                                  yRadius: max(0, radius - 0.5))
        border.lineWidth = 1
        border.stroke()
        image.unlockFocus()

        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    static func icon(for url: URL, isDirectory: Bool) -> NSImage {
        iconLock.lock()
        defer { iconLock.unlock() }
        let ext = url.pathExtension.lowercased()
        // .app 是应用程序包，即使底层是目录也要显示真实应用图标
        if ext == "app" {
            let key = url.path as NSString
            if let cached = appIcons.object(forKey: key) { return cached }
            let image = NSWorkspace.shared.icon(forFile: url.path)
            appIcons.setObject(image, forKey: key)
            return image
        }
        if isDirectory { return folderIcon }
        if ext.isEmpty { return genericIcon }
        let key = ext as NSString
        if let cached = extensionIcons.object(forKey: key) { return cached }
        let image = UTType(filenameExtension: ext).map { NSWorkspace.shared.icon(for: $0) } ?? genericIcon
        extensionIcons.setObject(image, forKey: key)
        return image
    }
}

enum FileSizeFormatter {
    static func string(_ bytes: Int64) -> String {
        if bytes < 1024 { return bytes == 0 ? "--" : "\(bytes) 字节" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes) / 1024
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: value >= 100 ? "%.0f" : "%.1f", value) + " " + units[index]
    }
}

enum DateFormatterStore {
    /// 文件列表/文件信息统一显示：2026/09/03 18:03
    static let medium: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()
}

final class FileClipboard {
    static let shared = FileClipboard()
    var urls: [URL] = []
    var operation: FileClipboardOperation = .copy
}

enum FileClipboardOperation {
    case copy
    case move
}

enum PaneViewMode: String {
    case icon
    case list
}

enum PaneSortKey: String {
    case name
    case modified
    case size
    case kind
}
