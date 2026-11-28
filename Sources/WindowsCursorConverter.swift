import AppKit

/// 独立实现的 Windows .ani/.cur → Mousecape .cape 转换器。
/// 解析 RIFF ACON / ANIH / ICON(DIB) 帧，自己完成 DIB → PNG、热点与缩放换算，
/// 不依赖任何第三方或 Mousecape-swiftUI 的代码。
enum WindowsCursorConverter {

    struct ConversionResult {
        let url: URL
        let themeName: String
        /// 源 Windows 光标种类数（未展开 macOS 别名）
        let cursorCount: Int
        /// 源动画帧总数（未展开 macOS 别名）
        let frameCount: Int
        /// 写入 .cape 的 macOS 标识数（含别名）
        let identifierCount: Int
        var skipped: Int = 0
    }

    // MARK: - 对外接口

    /// 把一个目录下的所有 .ani/.cur 合并为一个 .cape 主题
    static func convert(folder: URL) throws -> ConversionResult {
        let files = try WindowsCursorConverter.aniFiles(in: folder)
        guard !files.isEmpty else { throw ConverterError.noCursorFiles }
        return try convert(files: files, themeName: folder.lastPathComponent)
    }

    /// 把若干个 .ani/.cur 合并为一个 .cape 主题
    static func convert(files: [URL], themeName: String? = nil) throws -> ConversionResult {
        var cursors: [String: [String: Any]] = [:]
        var sourceIdentifiers = Set<String>()
        var sourceFrames = 0

        for file in files {
            let parsed = file.pathExtension.lowercased() == "cur"
                ? parseSingleCUR(file)
                : parseANI(file)
            guard let parsed else { continue }
            let identifier = macOSIdentifier(for: file.deletingPathExtension().lastPathComponent)
            if sourceIdentifiers.insert(identifier).inserted {
                sourceFrames += parsed.frameCount
            }
            for key in macOSIdentifiers(includingAliasesOf: identifier) {
                cursors[key] = parsed.dictionary
            }
        }
        guard !cursors.isEmpty else { throw ConverterError.unsupportedFile }

        let name = (themeName ?? files.first?.deletingPathExtension().lastPathComponent ?? "Windows 光标")
        return try writeTheme(name: name, author: "Windows 光标导入", cursors: cursors,
                              sourceCursorCount: sourceIdentifiers.count, sourceFrames: sourceFrames,
                              skipped: 0)
    }

    /// 按 Windows 光标安装 INF（如“~右键安装.inf”）的 Wreg 注册项批量转换。
    /// [Strings] 提供主题名与 %别名%，[Wreg] 把 Windows 光标角色映射到具体文件。
    static func convert(inf: URL) throws -> ConversionResult {
        guard let data = try? Data(contentsOf: inf) else { throw ConverterError.unsupportedFile }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: gb18030)
            ?? ""
        guard !text.isEmpty else { throw ConverterError.infParseFailed }

        var strings: [String: String] = [:]
        var roleValues: [(role: String, value: String)] = []
        var section = ""

        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces).lowercased()
                continue
            }
            switch section {
            case "strings":
                guard let equal = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<equal]).trimmingCharacters(in: .whitespaces).lowercased()
                var value = String(line[line.index(after: equal)...])
                    .trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                if !key.isEmpty { strings[key] = value }
            case "wreg":
                let fields = infFields(line)
                guard fields.count >= 5, fields[0].lowercased() == "hkcu",
                      fields[1].lowercased() == "control panel\\cursors" else { continue }
                let role = fields[2].trimmingCharacters(in: .whitespaces)
                let value = fields[fields.count - 1].trimmingCharacters(in: .whitespaces)
                if !role.isEmpty, !value.isEmpty {
                    roleValues.append((role: role, value: value))
                }
            default:
                break
            }
        }

        let name = strings["scheme_name"] ?? inf.deletingPathExtension().lastPathComponent
        var cursors: [String: [String: Any]] = [:]
        var sourceIdentifiers = Set<String>()
        var sourceFrames = 0
        var skipped = 0

        for entry in roleValues {
            guard let file = resolveINFFile(entry.value, strings: strings, inf: inf),
                  let parsed = file.pathExtension.lowercased() == "cur"
                    ? parseSingleCUR(file) : parseANI(file) else {
                skipped += 1
                continue
            }
            let filename = file.deletingPathExtension().lastPathComponent
            let identifier = identifier(forWindowsRole: entry.role, filename: filename)
            if sourceIdentifiers.insert(identifier).inserted {
                sourceFrames += parsed.frameCount
            }
            for key in macOSIdentifiers(includingAliasesOf: identifier) {
                cursors[key] = parsed.dictionary
            }
        }
        guard !cursors.isEmpty else { throw ConverterError.noCursorFiles }

        return try writeTheme(name: name, author: "Windows 光标导入 · INF", cursors: cursors,
                              sourceCursorCount: sourceIdentifiers.count, sourceFrames: sourceFrames,
                              skipped: skipped)
    }

    private static func writeTheme(name: String, author: String,
                                   cursors: [String: [String: Any]],
                                   sourceCursorCount: Int, sourceFrames: Int,
                                   skipped: Int) throws -> ConversionResult {
        let cape: [String: Any] = [
            "CapeName": name,
            "Author": author,
            "Identifier": "local.ani." + sanitized(name),
            "Version": 2.0,
            "MinimumVersion": 2.0,
            "HiDPI": true,
            "Cloud": false,
            "Cursors": cursors
        ]

        let directory = URL(fileURLWithPath: MousecapeBridge.capesDirectory(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var destination = directory.appendingPathComponent(sanitized(name) + ".cape")
        var index = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(sanitized(name))-\(index).cape")
            index += 1
        }
        guard (cape as NSDictionary).write(to: destination, atomically: true) else {
            throw ConverterError.writeFailed
        }
        return ConversionResult(url: destination, themeName: name,
                                cursorCount: sourceCursorCount, frameCount: sourceFrames,
                                identifierCount: cursors.count, skipped: skipped)
    }

    enum ConverterError: LocalizedError {
        case noCursorFiles
        case unsupportedFile
        case writeFailed
        case infParseFailed

        var errorDescription: String? {
            switch self {
            case .noCursorFiles: return "目录中没有找到 .ani 或 .cur 文件。"
            case .unsupportedFile: return "无法识别该光标文件，仅支持 Windows .ani / .cur。"
            case .writeFailed: return "写入 .cape 主题文件失败。"
            case .infParseFailed: return "无法解析该 INF 文件，请确认是正确的 Windows 光标安装配置。"
            }
        }
    }

    // MARK: - 文件发现

    static func aniFiles(in folder: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        return contents.filter {
            ["ani", "cur"].contains($0.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - RIFF / ANI 解析

    private struct ParsedCursor {
        let dictionary: [String: Any]
        let frameCount: Int
    }

    private static func parseANI(_ url: URL) -> ParsedCursor? {
        guard let data = try? Data(contentsOf: url), data.count >= 24,
              fourCC(data, 0) == "RIFF", fourCC(data, 8) == "ACON" else { return nil }

        var frameData: [Data] = []
        var displayRate: UInt32 = 2
        var pos = 12
        while pos + 8 <= data.count {
            let id = fourCC(data, pos)
            let size = Int(readUInt32(data, pos + 4))
            let payload = pos + 8
            guard payload + size <= data.count else { break }
            if id == "anih", size >= 36 {
                // ANIH: cbSize(0) nFrames(4) nSteps(8) iWidth(12) iHeight(16)
                //       iBitCount(20) nPlanes(24) iDispRate(28)
                let rate = readUInt32(data, payload + 28)
                if rate > 0 { displayRate = rate }
            } else if id == "LIST", fourCC(data, payload) == "fram" {
                var sub = payload + 4
                let end = payload + size
                while sub + 8 <= end {
                    let subID = fourCC(data, sub)
                    let subSize = Int(readUInt32(data, sub + 4))
                    let subPayload = sub + 8
                    guard subPayload + subSize <= end else { break }
                    if subID == "icon" {
                        frameData.append(Data(data[subPayload..<(subPayload + subSize)]))
                    }
                    sub += 8 + subSize + (subSize & 1)
                }
            }
            pos = payload + size + (size & 1)
        }
        guard !frameData.isEmpty, let first = parseCUR(frameData[0]) else { return nil }

        var images: [Data] = []
        for frame in frameData {
            guard let png = parseCUR(frame)?.png else { continue }
            images.append(png)
        }
        guard !images.isEmpty else { return nil }

        // Windows 光标标准逻辑尺寸为 32pt；96px 的 3x 图自动换算为 32pt
        let divisor = max(1, Int(round(Double(first.pixelWidth) / 32.0)))
        let pointsWide = max(1, Int(round(Double(first.pixelWidth) / Double(divisor))))
        let pointsHigh = max(1, Int(round(Double(first.pixelHeight) / Double(divisor))))
        let duration = min(1.0, max(0.01, Double(displayRate) / 60.0))
        // Mousecape 的动画帧放在一张纵向 sprite sheet 里，而不是每个 representation 一帧。
        // 统一成 2x（32pt → 64px），与 Mousecape 的 HiDPI cape 格式一致。
        let representations = spriteSheetPNG(images, frameSize: pointsWide * 2).map { [$0] } ?? images

        let dictionary: [String: Any] = [
            "FrameCount": images.count,
            "FrameDuration": duration,
            "HotSpotX": Double(first.hotspotX) / Double(divisor),
            "HotSpotY": Double(first.hotspotY) / Double(divisor),
            "PointsWide": pointsWide,
            "PointsHigh": pointsHigh,
            "Representations": representations
        ]
        return ParsedCursor(dictionary: dictionary, frameCount: images.count)
    }

    /// 单个 .cur 静态光标
    private static func parseSingleCUR(_ url: URL) -> ParsedCursor? {
        guard let data = try? Data(contentsOf: url),
              let frame = parseCUR(data), let png = frame.png else { return nil }
        let divisor = max(1, Int(round(Double(frame.pixelWidth) / 32.0)))
        let pointsWide = max(1, Int(round(Double(frame.pixelWidth) / Double(divisor))))
        let pointsHigh = max(1, Int(round(Double(frame.pixelHeight) / Double(divisor))))
        let representations = spriteSheetPNG([png], frameSize: pointsWide * 2).map { [$0] } ?? [png]
        let dictionary: [String: Any] = [
            "FrameCount": 1,
            "FrameDuration": 0.1,
            "HotSpotX": Double(frame.hotspotX) / Double(divisor),
            "HotSpotY": Double(frame.hotspotY) / Double(divisor),
            "PointsWide": pointsWide,
            "PointsHigh": pointsHigh,
            "Representations": representations
        ]
        return ParsedCursor(dictionary: dictionary, frameCount: 1)
    }

    // MARK: - CUR / DIB 解析

    private struct ParsedFrame {
        let png: Data?
        let pixelWidth: Int
        let pixelHeight: Int
        let hotspotX: Int
        let hotspotY: Int
    }

    private static func parseCUR(_ data: Data) -> ParsedFrame? {
        guard data.count >= 22, fourCC(data, 0) == "\0\0\u{02}\0" else { return nil }
        let count = Int(readUInt16(data, 4))
        guard count > 0 else { return nil }

        var width = Int(data[data.index(data.startIndex, offsetBy: 6)])
        var height = Int(data[data.index(data.startIndex, offsetBy: 7)])
        let hotX = Int(readUInt16(data, 10))
        let hotY = Int(readUInt16(data, 12))
        let imageSize = Int(readUInt32(data, 14))
        var offset = Int(readUInt32(data, 18))
        if width == 0 { width = 256 }
        if height == 0 { height = 256 }
        guard offset + 40 <= data.count else { return nil }

        // 有些 CUR 的第一张图不是 32bpp，优先找 32bpp 条目
        let entryCount = min(count, 64)
        for i in 0..<entryCount {
            let e = 6 + i * 16
            guard e + 16 <= data.count else { break }
            let bpp = Int(readUInt16(data, e + 10))
            let candidateOffset = Int(readUInt32(data, e + 14))
            if bpp == 32 { offset = candidateOffset; break }
        }

        let headerSize = Int(readUInt32(data, offset))
        guard headerSize >= 40, offset + headerSize <= data.count else { return nil }
        let dibWidth = Int(readInt32(data, offset + 4))
        let dibHeight = Int(readInt32(data, offset + 8))
        let bpp = Int(readUInt16(data, offset + 14))
        let compression = readUInt32(data, offset + 16)
        guard dibWidth > 0, dibHeight != 0, compression == 0 else { return nil }

        let imageHeight = abs(dibHeight) / 2
        guard imageHeight > 0 else { return nil }
        let xorStride = ((dibWidth * bpp + 31) / 32) * 4
        let andStride = ((dibWidth + 31) / 32) * 4
        let paletteCount = bpp <= 8
            ? max(1, min(256, Int(pow(2.0, Double(bpp)))))
            : 0
        let xorStart = offset + headerSize + paletteCount * 4
        let andStart = xorStart + xorStride * imageHeight
        guard andStart + andStride * imageHeight <= data.count, imageSize > 0 else {
            return ParsedFrame(png: nil, pixelWidth: width, pixelHeight: height,
                               hotspotX: hotX, hotspotY: hotY)
        }

        var palette: [(UInt8, UInt8, UInt8)] = []
        if bpp <= 8 {
            for i in 0..<paletteCount {
                let p = offset + headerSize + i * 4
                palette.append((data[data.index(data.startIndex, offsetBy: p + 2)],
                                data[data.index(data.startIndex, offsetBy: p + 1)],
                                data[data.index(data.startIndex, offsetBy: p)]))
            }
        }

        let w = dibWidth, h = imageHeight
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        var hasRealAlpha = false
        if bpp == 32 {
            for y in 0..<h {
                let src = xorStart + (h - 1 - y) * xorStride
                for x in 0..<w {
                    let p = src + x * 4
                    if data[data.index(data.startIndex, offsetBy: p + 3)] != 0 { hasRealAlpha = true }
                }
            }
        }

        for y in 0..<h {
            let xorRow = xorStart + (h - 1 - y) * xorStride
            let andRow = andStart + (h - 1 - y) * andStride
            for x in 0..<w {
                var r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0, a: UInt8 = 255
                switch bpp {
                case 32:
                    let p = xorRow + x * 4
                    b = data[data.index(data.startIndex, offsetBy: p)]
                    g = data[data.index(data.startIndex, offsetBy: p + 1)]
                    r = data[data.index(data.startIndex, offsetBy: p + 2)]
                    let stored = data[data.index(data.startIndex, offsetBy: p + 3)]
                    a = hasRealAlpha ? stored : 255
                case 24:
                    let p = xorRow + x * 3
                    b = data[data.index(data.startIndex, offsetBy: p)]
                    g = data[data.index(data.startIndex, offsetBy: p + 1)]
                    r = data[data.index(data.startIndex, offsetBy: p + 2)]
                case 8, 4, 1:
                    let index: Int
                    if bpp == 8 {
                        index = Int(data[data.index(data.startIndex, offsetBy: xorRow + x)])
                    } else {
                        let bit = bpp == 4 ? (x % 2) * 4 : (7 - (x % 8))
                        let byte = data[data.index(data.startIndex, offsetBy: xorRow + x / (bpp == 4 ? 2 : 8))]
                        index = Int((byte >> bit) & UInt8(bpp == 4 ? 0x0F : 0x01))
                    }
                    if index < palette.count {
                        (r, g, b) = palette[index]
                    }
                default:
                    break
                }
                let maskBit = (data[data.index(data.startIndex, offsetBy: andRow + x / 8)] >> (7 - (x % 8))) & 1
                if maskBit != 0 { a = 0 }
                let o = (y * w + x) * 4
                rgba[o] = r; rgba[o + 1] = g; rgba[o + 2] = b; rgba[o + 3] = a
            }
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32
        ), let pixels = bitmap.bitmapData else {
            return ParsedFrame(png: nil, pixelWidth: width, pixelHeight: height,
                               hotspotX: hotX, hotspotY: hotY)
        }
        for i in 0..<rgba.count { pixels[i] = rgba[i] }
        let png = bitmap.representation(using: .png, properties: [:])
        return ParsedFrame(png: png, pixelWidth: width, pixelHeight: height,
                           hotspotX: hotX, hotspotY: hotY)
    }

    // MARK: - INF 辅助

    /// 按逗号拆分 INF 行，忽略引号内的逗号与行尾注释
    private static func infFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
                continue
            }
            if !quoted && (character == ";" || character == "#") { break }
            if character == "," && !quoted {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    /// 展开 INF 中的 %别名%，未知项（如 %10%）按空处理
    private static func expand(_ value: String, using strings: [String: String]) -> String {
        var result = value
        for _ in 0..<10 {
            var next = result
            for (key, replacement) in strings {
                next = next.replacingOccurrences(of: "%\(key)%", with: replacement,
                                                 options: [.caseInsensitive])
            }
            next = next.replacingOccurrences(of: "%10%", with: "", options: [.caseInsensitive])
            if next == result { break }
            result = next
        }
        return result
    }

    /// INF 里的路径是 Windows 绝对路径；优先按同目录相对路径找，再退回按文件名找
    private static func resolveINFFile(_ value: String, strings: [String: String],
                                       inf: URL) -> URL? {
        var path = expand(value, using: strings)
        if let colon = path.lastIndex(of: ":") {
            path = String(path[path.index(after: colon)...])
        }
        path = path.replacingOccurrences(of: "\\", with: "/")
        let folder = inf.deletingLastPathComponent()
        let relative = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let basename = (path as NSString).lastPathComponent
        let candidates = [folder.appendingPathComponent(relative),
                          folder.appendingPathComponent(basename)]
        for url in candidates {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                return url
            }
        }
        return nil
    }

    /// Windows 注册表中的光标角色 → macOS 光标标识
    private static let windowsRoleIdentifiers: [String: String] = [
        "appstarting": "com.apple.cursor.4",
        "arrow": "com.apple.coregraphics.Arrow",
        "crosshair": "com.apple.cursor.7",
        "precisionhair": "com.apple.cursor.7",
        "hand": "com.apple.cursor.2",
        "help": "com.apple.cursor.40",
        "ibeam": "com.apple.coregraphics.IBeam",
        "no": "com.apple.cursor.3",
        "nwpen": "com.apple.cursor.13",
        "sizeall": "com.apple.coregraphics.Move",
        "sizenesw": "com.apple.cursor.30",
        "sizens": "com.apple.cursor.23",
        "sizenwse": "com.apple.cursor.34",
        "sizewe": "com.apple.cursor.19",
        "uparrow": "com.apple.cursor.16",
        "wait": "com.apple.coregraphics.Wait",
        "person": "com.apple.cursor.10",
        "pin": "com.apple.cursor.41"
    ]

    private static func identifier(forWindowsRole role: String, filename: String) -> String {
        windowsRoleIdentifiers[role.lowercased()] ?? macOSIdentifier(for: filename)
    }

    /// 一个 Windows 光标在 macOS 上对应多个等效标识；只写主标识会让其它上下文回落系统默认，
    /// 看起来就是“应用后光标异常”。这里按 Mousecape 主题的常见分组展开。
    private static let macOSAliasGroups: [String: [String]] = [
        "com.apple.coregraphics.Arrow": [
            "com.apple.coregraphics.Arrow", "com.apple.coregraphics.ArrowCtx",
            "com.apple.coregraphics.ArrowS", "com.apple.cursor.24"
        ],
        "com.apple.coregraphics.IBeam": [
            "com.apple.coregraphics.IBeam", "com.apple.coregraphics.IBeamS",
            "com.apple.coregraphics.IBeamXOR", "com.apple.cursor.26"
        ],
        "com.apple.coregraphics.Wait": ["com.apple.coregraphics.Wait"],
        "com.apple.coregraphics.Move": ["com.apple.coregraphics.Move", "com.apple.cursor.39"],
        "com.apple.cursor.2": ["com.apple.cursor.2", "com.apple.cursor.13"],
        "com.apple.cursor.3": ["com.apple.cursor.3"],
        "com.apple.cursor.4": ["com.apple.cursor.4", "com.apple.cursor.14",
                               "com.apple.cursor.15", "com.apple.cursor.16"],
        "com.apple.cursor.7": ["com.apple.cursor.7", "com.apple.cursor.8",
                               "com.apple.cursor.20", "com.apple.cursor.41"],
        "com.apple.cursor.10": ["com.apple.cursor.10"],
        "com.apple.cursor.13": ["com.apple.cursor.2", "com.apple.cursor.13"],
        "com.apple.cursor.16": ["com.apple.cursor.4", "com.apple.cursor.14",
                                "com.apple.cursor.15", "com.apple.cursor.16"],
        "com.apple.cursor.19": ["com.apple.cursor.17", "com.apple.cursor.18",
                                "com.apple.cursor.19", "com.apple.cursor.27",
                                "com.apple.cursor.28", "com.apple.cursor.38"],
        "com.apple.cursor.23": ["com.apple.cursor.21", "com.apple.cursor.22",
                                "com.apple.cursor.23", "com.apple.cursor.31",
                                "com.apple.cursor.32", "com.apple.cursor.36"],
        "com.apple.cursor.30": ["com.apple.cursor.29", "com.apple.cursor.30",
                                "com.apple.cursor.37"],
        "com.apple.cursor.34": ["com.apple.cursor.33", "com.apple.cursor.34",
                                "com.apple.cursor.35"],
        "com.apple.cursor.40": ["com.apple.cursor.40"]
    ]

    private static func macOSIdentifiers(includingAliasesOf identifier: String) -> [String] {
        macOSAliasGroups[identifier] ?? [identifier]
    }

    /// 把各帧缩放为 2x 后纵向拼成一张 sprite sheet，Mousecape 用一张图 + FrameCount 表示动画。
    private static func spriteSheetPNG(_ frames: [Data], frameSize: Int) -> Data? {
        guard !frames.isEmpty, frameSize > 0 else { return nil }
        let reps = frames.compactMap { resizedBitmap($0, to: frameSize) }
        guard reps.count == frames.count else { return nil }

        let frameBytes = frameSize * frameSize * 4
        guard let sheet = NSBitmapImageRep(bitmapDataPlanes: nil,
                                           pixelsWide: frameSize,
                                           pixelsHigh: frameSize * reps.count,
                                           bitsPerSample: 8, samplesPerPixel: 4,
                                           hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB,
                                           bytesPerRow: frameSize * 4,
                                           bitsPerPixel: 32),
              let destination = sheet.bitmapData else { return nil }

        for (index, rep) in reps.enumerated() {
            guard let source = rep.bitmapData else { return nil }
            destination.advanced(by: index * frameBytes).update(from: source, count: frameBytes)
        }
        return sheet.representation(using: .png, properties: [:])
    }

    private static func resizedBitmap(_ png: Data, to size: Int) -> NSBitmapImageRep? {
        guard let image = NSImage(data: png),
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: size * 4,
                                         bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func macOSIdentifier(for filename: String) -> String {
        let name = filename.lowercased()
        let rules: [(String, String)] = [
            ("normal select", "com.apple.coregraphics.Arrow"),
            ("arrow", "com.apple.coregraphics.Arrow"),
            ("text select", "com.apple.coregraphics.IBeam"),
            ("ibeam", "com.apple.coregraphics.IBeam"),
            ("busy", "com.apple.coregraphics.Wait"),
            ("wait", "com.apple.coregraphics.Wait"),
            ("working in background", "com.apple.cursor.4"),
            ("precision select", "com.apple.cursor.7"),
            ("crosshair", "com.apple.cursor.7"),
            ("help select", "com.apple.cursor.40"),
            ("help", "com.apple.cursor.40"),
            ("handwriting", "com.apple.cursor.13"),
            ("unavailable", "com.apple.cursor.3"),
            ("vertical resize", "com.apple.cursor.23"),
            ("horizontal resize", "com.apple.cursor.19"),
            ("diagonal resize 1", "com.apple.cursor.34"),
            ("diagonal resize 2", "com.apple.cursor.30"),
            ("move", "com.apple.coregraphics.Move"),
            ("alternate select", "com.apple.cursor.16"),
            ("link select", "com.apple.cursor.2"),
            ("location select", "com.apple.cursor.10"),
            ("person select", "com.apple.cursor.41")
        ]
        for (keyword, identifier) in rules where name.contains(keyword) { return identifier }
        return "com.apple.coregraphics.Arrow"
    }

    private static func sanitized(_ name: String) -> String {
        let allowed = name.unicodeScalars.map { scalar -> String in
            if scalar.properties.isAlphabetic || scalar.value >= 0x4E00 { return String(scalar) }
            if CharacterSet.decimalDigits.contains(scalar) { return String(scalar) }
            return "-"
        }.joined()
        let collapsed = allowed.split(separator: "-").filter { !$0.isEmpty }.joined(separator: "-")
        return collapsed.isEmpty ? "WindowsCursor" : collapsed
    }

    private static func fourCC(_ data: Data, _ offset: Int) -> String {
        guard offset + 4 <= data.count else { return "" }
        let bytes = [UInt8](data[data.index(data.startIndex, offsetBy: offset)..<data.index(data.startIndex, offsetBy: offset + 4)])
        return String(bytes.map { Character(UnicodeScalar($0)) })
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        let b0 = UInt16(data[data.index(data.startIndex, offsetBy: offset)])
        let b1 = UInt16(data[data.index(data.startIndex, offsetBy: offset + 1)]) << 8
        return b0 | b1
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(data[data.index(data.startIndex, offsetBy: offset + i)]) << (8 * i)
        }
        return value
    }

    private static func readInt32(_ data: Data, _ offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32(data, offset))
    }
}
