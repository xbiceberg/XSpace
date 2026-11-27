import Foundation
import AppKit
import CoreImage
import CoreGraphics
import CryptoKit
import Vision

enum ScreenCapture {

    /// 先抓取当前屏幕位图，覆盖层出现前的画面会作为编辑底图。
    static func screenImage() -> NSImage? {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xspace_screen_\(UUID().uuidString).png")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-t", "png", tempURL.path]
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let image = NSImage(contentsOf: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
            return image
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
    }

    /// 把编辑后的图片保存到设置里的目录（默认「文稿」），返回最终文件地址。
    @discardableResult
    static func saveScreenshot(_ image: NSImage) -> URL? {
        let directory = AppSettings.screenshotDirectory
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let base = "XSpace 截图 \(formatter.string(from: Date()))"
        var url = directory.appendingPathComponent("\(base).png")
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base) (\(index)).png")
            index += 1
        }
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    static func copyToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}

// MARK: - 区域截图编辑器（工具栏对齐系统截图）

final class ScreenshotEditorView: NSView {
    /// 工具：矩形、椭圆、画笔、箭头、马赛克、文字
    enum Tool: Int, CaseIterable {
        case rectangle, ellipse, pen, arrow, mosaic, text
    }

    enum Mode { case selecting, editing }

    /// 选区边框上的 8 个缩放控制点（四角 + 四边中点）
    private enum ResizeHandle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var cursor: NSCursor {
            switch self {
            case .topLeft, .bottomRight, .topRight, .bottomLeft: return .crosshair
            case .top, .bottom: return .resizeUpDown
            case .left, .right: return .resizeLeftRight
            }
        }
    }

    /// 马赛克笔刷：按住鼠标涂抹成马赛克，像铅笔/橡皮擦一样
    enum MosaicBrush {
        /// 涂抹直径（点）
        static let diameter: CGFloat = 24
        /// 马赛克方块边长（点）
        static let block: CGFloat = 10
    }

    /// 整块选区的马赛克底图：涂抹时按笔迹裁剪后贴回，保证多笔之间颗粒对齐
    struct MosaicTile {
        let image: NSImage
        let size: NSSize
    }

    /// 标注的绘制上下文：`shift` 把视图坐标换算到当前坐标系，
    /// `selectionFrame` 是选区在当前坐标系中的位置（马赛克底图就贴在这里）
    struct DrawContext {
        var shift: NSPoint
        var selectionFrame: NSRect

        /// 画布上：坐标不偏移，选区就是选区本身
        static func canvas(_ selection: NSRect) -> DrawContext {
            DrawContext(shift: .zero, selectionFrame: selection)
        }

        /// 导出时：坐标平移到选区左下角，选区从 (0,0) 开始
        static func export(_ selection: NSRect) -> DrawContext {
            DrawContext(shift: selection.origin,
                        selectionFrame: NSRect(origin: .zero, size: selection.size))
        }

        func local(_ point: NSPoint) -> NSPoint {
            NSPoint(x: point.x - shift.x, y: point.y - shift.y)
        }
    }

    struct Annotation {
        var tool: Tool
        var rect: NSRect = .zero
        var points: [NSPoint] = []
        var colorIndex: Int = 0
        var text: String = ""
        /// 文字字号（只对 .text 有效）
        var fontSize: CGFloat = ScreenshotEditorView.defaultFontSize

        /// 在当前坐标系中绘制
        func draw(in context: DrawContext, background: NSImage?, mosaic: MosaicTile?) {
            let local = rect.offsetBy(dx: -context.shift.x, dy: -context.shift.y)
            let color = ScreenshotEditorView.palette[min(colorIndex, ScreenshotEditorView.palette.count - 1)]

            switch tool {
            case .rectangle:
                ScreenshotEditorView.stroke(NSBezierPath(rect: local), color: color)
            case .ellipse:
                ScreenshotEditorView.stroke(NSBezierPath(ovalIn: local), color: color)
            case .pen:
                let path = NSBezierPath()
                for (index, point) in points.enumerated() {
                    let shifted = context.local(point)
                    if index == 0 { path.move(to: shifted) } else { path.line(to: shifted) }
                }
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                ScreenshotEditorView.stroke(path, color: color, width: 3)
            case .arrow:
                guard let first = points.first, let last = points.last else { return }
                ScreenshotEditorView.drawArrow(from: context.local(first),
                                               to: context.local(last),
                                               color: color)
            case .mosaic:
                ScreenshotEditorView.drawMosaic(stroke: strokePath(context: context),
                                                at: context.selectionFrame.origin,
                                                tile: mosaic)
            case .text:
                ScreenshotEditorView.drawText(text, at: local.origin, color: color, fontSize: fontSize)
            }
        }

        /// 涂抹笔迹：与画笔相同的折线，线宽即马赛克直径；返回的是「描边轮廓」，
        /// 因为裁剪只认填充区域，细线本身没有面积，必须先转成带宽度的轮廓
        private func strokePath(context: DrawContext) -> NSBezierPath {
            let shifted = points.map { context.local($0) }
            guard let first = shifted.first else { return NSBezierPath() }

            let xs = shifted.map(\.x)
            let ys = shifted.map(\.y)
            let spread = NSSize(width: (xs.max() ?? 0) - (xs.min() ?? 0),
                                height: (ys.max() ?? 0) - (ys.min() ?? 0))
            let diameter = ScreenshotEditorView.MosaicBrush.diameter
            let radius = diameter / 2
            // 单击或原地按下的点涂：直接用圆点，避免零长度线段画不出来
            if spread.width < 0.5 && spread.height < 0.5 {
                return NSBezierPath(ovalIn: NSRect(x: first.x - radius, y: first.y - radius,
                                                   width: radius * 2, height: radius * 2))
            }

            let line = NSBezierPath()
            line.move(to: first)
            for point in shifted.dropFirst() { line.line(to: point) }
            let outline = line.cgPath.copy(strokingWithWidth: diameter,
                                           lineCap: .round,
                                           lineJoin: .round,
                                           miterLimit: 10,
                                           transform: .identity)
            return NSBezierPath(cgPath: outline)
        }
    }

    static let palette: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .white]
    /// 文字工具可选字号
    static let fontSizeOptions: [CGFloat] = [12, 16, 20, 24, 32, 40, 48, 64]
    static let defaultFontSize: CGFloat = 24

    var backgroundImage: NSImage?
    var mode: Mode = .selecting
    var selectionRect: NSRect = .zero
    var activeTool: Tool = .rectangle {
        didSet {
            selectedAnnotationIndex = nil
            annotationInteraction = nil
            needsDisplay = true
        }
    }
    var activeColorIndex = 0
    var activeFontSize: CGFloat = ScreenshotEditorView.defaultFontSize

    var onSelectionDone: (() -> Void)?
    var onCancel: (() -> Void)?
    var onChange: (() -> Void)?
    /// 选区完成后按回车：等同点击工具栏的绿色「勾」
    var onConfirm: (() -> Void)?

    private var selectionStart: NSPoint = .zero
    private var activeResizeHandle: ResizeHandle?
    private var resizeStartRect: NSRect = .zero
    /// 当前选中的矩形/椭圆标注；绘制完成后自动选中，可拖动控制点或框体
    private var selectedAnnotationIndex: Int?
    private enum AnnotationInteraction {
        case resize(ResizeHandle)
        case resizeArrow(Int)
        case move
    }
    private var annotationInteraction: AnnotationInteraction?
    private var annotationStartRect: NSRect = .zero
    private var annotationStartPoint: NSPoint = .zero
    private var annotationStartPoints: [NSPoint] = []
    private var annotations: [Annotation] = []
    private var draft: Annotation?
    private var annotationStart: NSPoint = .zero
    private var textField: NSTextField?
    /// 选区马赛克底图缓存（选区变化时重建）
    private var mosaicTileCache: (rect: NSRect, tile: MosaicTile?)?

    override var acceptsFirstResponder: Bool { true }

    // MARK: - 鼠标

    /// 截图过程中点击鼠标右键：取消截图（与 Esc 一致）
    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch mode {
        case .selecting:
            selectionStart = point
            selectionRect = .zero
        case .editing:
            commitPendingText()
            // 已选中的标注：先命中控制点，其次命中标注本身
            if let index = selectedAnnotationIndex, annotations.indices.contains(index) {
                let item = annotations[index]
                if item.tool == .arrow {
                    if let endpoint = arrowHandle(at: point, index: index) {
                        annotationInteraction = .resizeArrow(endpoint)
                        annotationStartPoints = item.points
                        NSCursor.crosshair.set()
                        needsDisplay = true
                        return
                    }
                    if Self.distance(from: point, to: item.points.first ?? .zero,
                                     end: item.points.last ?? .zero) <= 8 {
                        annotationInteraction = .move
                        annotationStartPoints = item.points
                        annotationStartPoint = point
                        needsDisplay = true
                        return
                    }
                } else {
                    if let handle = annotationHandle(at: point, index: index) {
                        annotationInteraction = .resize(handle)
                        annotationStartRect = item.rect
                        handle.cursor.set()
                        needsDisplay = true
                        return
                    }
                    if item.rect.insetBy(dx: -6, dy: -6).contains(point) {
                        annotationInteraction = .move
                        annotationStartRect = item.rect
                        annotationStartPoint = point
                        needsDisplay = true
                        return
                    }
                }
                selectedAnnotationIndex = nil
            }
            // 选区边框控制点：拖动改截图范围
            if let handle = resizeHandle(at: point) {
                activeResizeHandle = handle
                resizeStartRect = selectionRect
                handle.cursor.set()
                needsDisplay = true
                return
            }
            // 点中已有的矩形/椭圆/箭头标注则选中它，而不是再画一个新标注
            if activeTool == .rectangle || activeTool == .ellipse || activeTool == .arrow,
               let index = editableAnnotationIndex(at: point) {
                selectedAnnotationIndex = index
                let item = annotations[index]
                annotationInteraction = .move
                annotationStartPoint = point
                if item.tool == .arrow {
                    annotationStartPoints = item.points
                } else {
                    annotationStartRect = item.rect
                }
                needsDisplay = true
                return
            }
            guard selectionRect.contains(point) else { needsDisplay = true; return }
            switch activeTool {
            case .text:
                selectedAnnotationIndex = nil
                beginText(at: point)
            default:
                selectedAnnotationIndex = nil
                annotationStart = point
                draft = Annotation(tool: activeTool,
                                   rect: NSRect(x: point.x, y: point.y, width: 0, height: 0),
                                   points: [point, point],
                                   colorIndex: activeColorIndex)
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch mode {
        case .selecting:
            selectionRect = Self.normalized(from: selectionStart, to: point)
        case .editing:
            if let index = selectedAnnotationIndex,
               annotations.indices.contains(index),
               let interaction = annotationInteraction {
                switch interaction {
                case .resize(let handle):
                    annotations[index].rect = Self.resizedRect(from: annotationStartRect,
                                                               handle: handle,
                                                               to: point,
                                                               limits: selectionRect)
                case .resizeArrow(let endpoint):
                    guard annotationStartPoints.indices.contains(endpoint) else { return }
                    var points = annotationStartPoints
                    points[endpoint] = Self.clampPoint(point, to: selectionRect)
                    annotations[index].points = points
                    annotations[index].rect = Self.boundingRect(of: points)
                case .move:
                    if annotations[index].tool == .arrow {
                        let dx = point.x - annotationStartPoint.x
                        let dy = point.y - annotationStartPoint.y
                        let points = annotationStartPoints.map { Self.clampPoint(NSPoint(x: $0.x + dx, y: $0.y + dy), to: selectionRect) }
                        annotations[index].points = points
                        annotations[index].rect = Self.boundingRect(of: points)
                    } else {
                        var rect = annotationStartRect
                        rect.origin.x += point.x - annotationStartPoint.x
                        rect.origin.y += point.y - annotationStartPoint.y
                        annotations[index].rect = Self.clampAnnotationRect(rect, to: selectionRect)
                    }
                }
                needsDisplay = true
                return
            }
            if let handle = activeResizeHandle {
                selectionRect = Self.resizedRect(from: resizeStartRect,
                                                 handle: handle,
                                                 to: point,
                                                 limits: bounds)
                handle.cursor.set()
                needsDisplay = true
                return
            }
            guard var item = draft else { return }
            item.rect = Self.normalized(from: annotationStart, to: point)
            if item.tool == .pen || item.tool == .mosaic {
                // 画笔与马赛克都记录完整轨迹，实现「按住涂抹」
                item.points.append(point)
            } else {
                item.points = [annotationStart, point]
            }
            draft = item
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch mode {
        case .selecting:
            selectionRect = Self.normalized(from: selectionStart, to: point)
            if selectionRect.width < 12 || selectionRect.height < 12 {
                selectionRect = .zero
                onCancel?()
            } else {
                mode = .editing
                onSelectionDone?()
            }
        case .editing:
            if annotationInteraction != nil {
                annotationInteraction = nil
                NSCursor.arrow.set()
                needsDisplay = true
                return
            }
            if activeResizeHandle != nil {
                activeResizeHandle = nil
                NSCursor.arrow.set()
                needsDisplay = true
                return
            }
            if var item = draft {
                item.rect = Self.normalized(from: annotationStart, to: point)
                switch item.tool {
                case .pen:
                    item.points.append(point)
                    if item.points.count > 2 { annotations.append(item) }
                case .mosaic:
                    // 点一下也算一笔（点状涂抹），划一下就是一道笔迹
                    item.points.append(point)
                    annotations.append(item)
                case .arrow:
                    item.points = [annotationStart, point]
                    if hypot(point.x - annotationStart.x, point.y - annotationStart.y) > 12 {
                        annotations.append(item)
                        // 箭头画完就选中，显示首尾两个可拖动控制点
                        selectedAnnotationIndex = annotations.count - 1
                    }
                default:
                    if max(item.rect.width, item.rect.height) > 8 {
                        annotations.append(item)
                        // 矩形/椭圆画完就选中，直接显示可拖动的 8 个控制点
                        if item.tool == .rectangle || item.tool == .ellipse {
                            selectedAnnotationIndex = annotations.count - 1
                        }
                    }
                }
                draft = nil
                onChange?()
            }
        }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard mode == .editing else { NSCursor.arrow.set(); return }
        if let index = selectedAnnotationIndex, annotations.indices.contains(index) {
            let item = annotations[index]
            if item.tool == .arrow {
                if arrowHandle(at: point, index: index) != nil {
                    NSCursor.crosshair.set()
                    return
                }
                if Self.distance(from: point, to: item.points.first ?? .zero,
                                 end: item.points.last ?? .zero) <= 8 {
                    NSCursor.openHand.set()
                    return
                }
            } else {
                if let handle = annotationHandle(at: point, index: index) {
                    handle.cursor.set()
                    return
                }
                if item.rect.insetBy(dx: -6, dy: -6).contains(point) {
                    NSCursor.openHand.set()
                    return
                }
            }
        }
        if let handle = resizeHandle(at: point) {
            handle.cursor.set()
            return
        }
        NSCursor.arrow.set()
    }

    /// 控制点位置：四角 + 四边中点
    private func handleLocations(for rect: NSRect) -> [(handle: ResizeHandle, point: NSPoint)] {
        return [
            (.topLeft, NSPoint(x: rect.minX, y: rect.maxY)),
            (.top, NSPoint(x: rect.midX, y: rect.maxY)),
            (.topRight, NSPoint(x: rect.maxX, y: rect.maxY)),
            (.right, NSPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight, NSPoint(x: rect.maxX, y: rect.minY)),
            (.bottom, NSPoint(x: rect.midX, y: rect.minY)),
            (.bottomLeft, NSPoint(x: rect.minX, y: rect.minY)),
            (.left, NSPoint(x: rect.minX, y: rect.midY))
        ]
    }

    private func resizeHandle(at point: NSPoint) -> ResizeHandle? {
        guard !selectionRect.isEmpty else { return nil }
        let radius: CGFloat = 10
        return handleLocations(for: selectionRect).first { hypot($0.point.x - point.x, $0.point.y - point.y) <= radius }?.handle
    }

    /// 可编辑标注（矩形/椭圆/箭头）是否命中
    private func editableAnnotationIndex(at point: NSPoint) -> Int? {
        for index in annotations.indices {
            let item = annotations[index]
            switch item.tool {
            case .rectangle, .ellipse:
                if item.rect.insetBy(dx: -8, dy: -8).contains(point) { return index }
            case .arrow:
                if Self.distance(from: point, to: item.points.first ?? .zero,
                                 end: item.points.last ?? .zero) <= 8 { return index }
            default:
                break
            }
        }
        return nil
    }

    private func annotationHandle(at point: NSPoint, index: Int) -> ResizeHandle? {
        guard annotations.indices.contains(index) else { return nil }
        let radius: CGFloat = 10
        return handleLocations(for: annotations[index].rect)
            .first { hypot($0.point.x - point.x, $0.point.y - point.y) <= radius }?.handle
    }

    /// 箭头首尾控制点：返回点在 points 中的下标
    private func arrowHandle(at point: NSPoint, index: Int) -> Int? {
        guard annotations.indices.contains(index) else { return nil }
        let points = annotations[index].points
        guard points.count >= 2 else { return nil }
        let radius: CGFloat = 10
        for endpoint in [0, points.count - 1] {
            if hypot(point.x - points[endpoint].x, point.y - points[endpoint].y) <= radius {
                return endpoint
            }
        }
        return nil
    }

    private static func distance(from point: NSPoint, to start: NSPoint, end: NSPoint) -> CGFloat {
        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }

    private static func clampPoint(_ point: NSPoint, to limits: NSRect) -> NSPoint {
        NSPoint(x: min(max(point.x, limits.minX), limits.maxX),
                y: min(max(point.y, limits.minY), limits.maxY))
    }

    private static func boundingRect(of points: [NSPoint]) -> NSRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 标注拖动时限制在选区内，避免拖出截图范围后不可见
    private static func clampAnnotationRect(_ rect: NSRect, to limits: NSRect) -> NSRect {
        var result = rect
        result.origin.x = min(max(result.origin.x, limits.minX), max(limits.minX, limits.maxX - result.width))
        result.origin.y = min(max(result.origin.y, limits.minY), max(limits.minY, limits.maxY - result.height))
        return result
    }

    /// 按拖动的控制点调整选区；四角改两个方向，边中点只改一个方向
    private static func resizedRect(from rect: NSRect,
                                    handle: ResizeHandle,
                                    to rawPoint: NSPoint,
                                    limits: NSRect) -> NSRect {
        let minSide: CGFloat = 24
        let point = NSPoint(x: min(max(rawPoint.x, limits.minX), limits.maxX),
                            y: min(max(rawPoint.y, limits.minY), limits.maxY))
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        switch handle {
        case .left, .topLeft, .bottomLeft: minX = min(point.x, maxX - minSide)
        case .right, .topRight, .bottomRight: maxX = max(point.x, minX + minSide)
        default: break
        }
        switch handle {
        case .bottom, .bottomLeft, .bottomRight: minY = min(point.y, maxY - minSide)
        case .top, .topLeft, .topRight: maxY = max(point.y, minY + minSide)
        default: break
        }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc 取消截图
            onCancel?()
        case 36, 76: // Return / 小键盘回车：等同点击「勾」，完成并复制到剪贴板
            guard mode == .editing, !selectionRect.isEmpty else { return }
            onConfirm?()
        case 51, 117: // Delete 撤销最后一个标注
            undoLast()
        default:
            super.keyDown(with: event)
        }
    }

    /// Esc 也会走 cancelOperation（例如按钮持有焦点时）
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        // 先把抓取到的整屏画面铺满窗口，让整个屏幕在选区前就“定住”，
        // 底下实时变化的窗口/动画不会再透出来（与系统截图一致）。
        backgroundImage?.draw(in: bounds)
        // 选区外统一压暗，突出即将框选的区域
        NSColor.black.withAlphaComponent(0.42).setFill()
        NSBezierPath(rect: bounds).fill()
        guard !selectionRect.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selectionRect).addClip()
        // 选区内重画原始定格画面，覆盖掉压暗层，保持清晰
        backgroundImage?.draw(in: bounds)
        let tile = mosaicTileForDrawing()
        let context = DrawContext.canvas(selectionRect)
        for item in annotations { item.draw(in: context, background: backgroundImage, mosaic: tile) }
        draft?.draw(in: context, background: backgroundImage, mosaic: tile)
        NSGraphicsContext.restoreGraphicsState()

        drawSelectionChrome()
        drawAnnotationChrome()
    }

    /// 只有出现马赛克笔迹时才生成底图，避免每次重绘都做一次缩放
    private func mosaicTileForDrawing() -> MosaicTile? {
        let usesMosaic = annotations.contains { $0.tool == .mosaic } || draft?.tool == .mosaic
        guard usesMosaic else { return nil }
        if let cache = mosaicTileCache, cache.rect == selectionRect { return cache.tile }
        let tile = backgroundImage.flatMap {
            Self.makeMosaicTile(background: $0, selection: selectionRect, block: MosaicBrush.block)
        }
        mosaicTileCache = (selectionRect, tile)
        return tile
    }

    private func drawSelectionChrome() {
        let accent = NSColor.systemGreen
        let border = NSBezierPath(rect: selectionRect.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1.5
        if mode == .selecting {
            var pattern: [CGFloat] = [6, 4]
            border.setLineDash(&pattern, count: 2, phase: 0)
        }
        accent.setStroke()
        border.stroke()

        // 四角 + 四边中点，编辑选区时可拖动改大小
        let handleSize: CGFloat = 9
        for item in handleLocations(for: selectionRect) {
            let rect = NSRect(x: item.point.x - handleSize / 2,
                              y: item.point.y - handleSize / 2,
                              width: handleSize, height: handleSize)
            let dot = NSBezierPath(ovalIn: rect)
            dot.lineWidth = 1.5
            NSColor.white.setFill()
            accent.setStroke()
            dot.fill()
            dot.stroke()
        }

        drawSizeBadge()
    }

    /// 选中矩形/椭圆/箭头标注时叠加控制点；不受选区裁剪影响
    private func drawAnnotationChrome() {
        guard let index = selectedAnnotationIndex,
              annotations.indices.contains(index) else { return }
        let item = annotations[index]
        let color = ScreenshotEditorView.palette[min(item.colorIndex, ScreenshotEditorView.palette.count - 1)]
        let spots: [NSPoint]
        if item.tool == .arrow {
            spots = [item.points.first, item.points.last].compactMap { $0 }
        } else {
            spots = handleLocations(for: item.rect).map(\.point)
        }
        let handleSize: CGFloat = 9
        for point in spots {
            let rect = NSRect(x: point.x - handleSize / 2,
                              y: point.y - handleSize / 2,
                              width: handleSize, height: handleSize)
            let dot = NSBezierPath(ovalIn: rect)
            dot.lineWidth = 1.5
            NSColor.white.setFill()
            color.setStroke()
            dot.fill()
            dot.stroke()
        }
    }

    private func drawSizeBadge() {
        let text = "\(Int(selectionRect.width.rounded())) × \(Int(selectionRect.height.rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let padding = NSSize(width: 8, height: 4)
        var origin = NSPoint(x: selectionRect.minX, y: selectionRect.maxY + 6)
        let boxHeight = textSize.height + padding.height * 2
        if origin.y + boxHeight > bounds.maxY - 2 {
            origin.y = selectionRect.minY - boxHeight - 6
        }
        origin.y = max(2, min(origin.y, bounds.maxY - boxHeight - 2))

        let box = NSRect(x: origin.x, y: origin.y,
                         width: textSize.width + padding.width * 2,
                         height: boxHeight)
        let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.72).setFill()
        path.fill()
        NSColor.systemGreen.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 1
        path.stroke()
        (text as NSString).draw(at: NSPoint(x: box.minX + padding.width, y: box.minY + padding.height),
                                withAttributes: attributes)
    }

    // MARK: - 标注绘制工具

    private static func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat = 2.5) {
        let shadow = path.copy() as? NSBezierPath ?? path
        shadow.lineWidth = width + 2
        NSColor.black.withAlphaComponent(0.32).setStroke()
        shadow.stroke()
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    /// 箭头：一条带描边的直线 + 实心三角箭头，方向由起点指向终点
    private static func drawArrow(from start: NSPoint, to tip: NSPoint, color: NSColor) {
        let dx = tip.x - start.x
        let dy = tip.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return }
        let ux = dx / length
        let uy = dy / length
        let headLength = min(18, max(9, length * 0.22))
        let headHalfWidth = headLength * 0.48

        // 箭杆在箭头底部收住，避免穿过实心三角
        let shaftEnd = NSPoint(x: tip.x - ux * headLength * 0.8,
                               y: tip.y - uy * headLength * 0.8)
        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: shaftEnd)
        shaft.lineCapStyle = .round
        stroke(shaft, color: color, width: 3)

        let base = NSPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)
        let perpX = -uy * headHalfWidth
        let perpY = ux * headHalfWidth
        let head = NSBezierPath()
        head.move(to: tip)
        head.line(to: NSPoint(x: base.x + perpX, y: base.y + perpY))
        head.line(to: NSPoint(x: base.x - perpX, y: base.y - perpY))
        head.close()
        let shadow = head.copy() as? NSBezierPath ?? head
        NSColor.black.withAlphaComponent(0.32).setFill()
        shadow.fill()
        color.setFill()
        head.fill()
    }

    /// 马赛克：把缩好的方块底图按笔迹裁剪贴回画布，形成「橡皮擦式」涂抹
    private static func drawMosaic(stroke: NSBezierPath, at tileOrigin: NSPoint, tile: MosaicTile?) {
        guard let tile, !stroke.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        stroke.addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        tile.image.draw(in: NSRect(origin: tileOrigin, size: tile.size),
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 生成整块选区的马赛克底图：先缩小到「方块数」大小（等于按块取平均色），
    /// 画的时候再用「不插值」放大，颗粒始终对齐，多笔涂抹不会出现接缝
    static func makeMosaicTile(background: NSImage, selection: NSRect, block: CGFloat) -> MosaicTile? {
        guard selection.width >= 1, selection.height >= 1, block >= 1 else { return nil }
        let columns = max(1, Int((selection.width / block).rounded(.up)))
        let rows = max(1, Int((selection.height / block).rounded(.up)))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: columns,
                                         pixelsHigh: rows,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: columns, height: rows)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        background.draw(in: NSRect(x: 0, y: 0, width: columns, height: rows),
                        from: selection,
                        operation: .copy,
                        fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: columns, height: rows))
        image.addRepresentation(rep)
        return MosaicTile(image: image,
                          size: NSSize(width: CGFloat(columns) * block, height: CGFloat(rows) * block))
    }

    /// 文字统一用等宽权重一致的 semibold，颜色直接取当前的调色板（与矩形、椭圆共用）
    static func textFont(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    private static func drawText(_ text: String, at origin: NSPoint, color: NSColor, fontSize: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: textFont(size: fontSize),
            .foregroundColor: color
        ]
        NSAttributedString(string: text, attributes: attributes).draw(at: origin)
    }

    private static func normalized(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x),
               y: min(a.y, b.y),
               width: abs(a.x - b.x),
               height: abs(a.y - b.y))
    }

    // MARK: - 文字标注

    private func beginText(at point: NSPoint) {
        let size = activeFontSize
        let height = size + 8
        // 输入框纵向居中在点击位置，这样大字号也不会跑到鼠标上方
        let field = NSTextField(frame: NSRect(x: point.x,
                                              y: point.y - height / 2,
                                              width: 260,
                                              height: height))
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Self.textFont(size: size)
        field.textColor = Self.palette[min(activeColorIndex, Self.palette.count - 1)]
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.target = self
        field.action = #selector(textFieldAction(_:))
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    @objc private func textFieldAction(_ sender: NSTextField) {
        commitText(from: sender)
    }

    /// 提交正在编辑的文字（导出、切换工具、点击别处时调用）
    func commitPendingText() {
        guard let field = textField else { return }
        commitText(from: field)
    }

    /// 若正在输入文字则提交并返回 true（供 Esc 判断）
    @discardableResult
    func commitTextIfEditing() -> Bool {
        guard let field = textField else { return false }
        commitText(from: field)
        return true
    }

    private func commitText(from field: NSTextField) {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = field.frame.origin
        let size = field.font?.pointSize ?? activeFontSize
        let colorIndex = activeColorIndex
        textField = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        guard !text.isEmpty else { needsDisplay = true; return }
        var item = Annotation(tool: .text,
                              rect: NSRect(origin: origin, size: .zero),
                              colorIndex: colorIndex,
                              text: text,
                              fontSize: size)
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.textFont(size: size)]
        item.rect.size = (text as NSString).size(withAttributes: attributes)
        annotations.append(item)
        needsDisplay = true
        onChange?()
    }

    // MARK: - 对外操作

    func undoLast() {
        commitPendingText()
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        if let index = selectedAnnotationIndex, index >= annotations.count {
            selectedAnnotationIndex = nil
            annotationInteraction = nil
        }
        needsDisplay = true
        onChange?()
    }

    func resetSelection() {
        commitPendingText()
        annotations.removeAll()
        draft = nil
        mosaicTileCache = nil
        selectedAnnotationIndex = nil
        annotationInteraction = nil
        selectionRect = .zero
        mode = .selecting
        needsDisplay = true
        onChange?()
    }

    var hasAnnotations: Bool { !annotations.isEmpty }

    func resultImage() -> NSImage? {
        let size = selectionRect.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: width,
                                         pixelsHigh: height,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        backgroundImage?.draw(in: NSRect(origin: .zero, size: size),
                              from: selectionRect,
                              operation: .sourceOver,
                              fraction: 1)
        let tile = mosaicTileForDrawing()
        let context = DrawContext.export(selectionRect)
        for item in annotations {
            item.draw(in: context, background: backgroundImage, mosaic: tile)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}

/// 无边框窗口默认不能成为 key window，会导致 Esc / Delete 收不到键盘事件
private final class ScreenshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ScreenshotEditorController: NSObject {
    static let shared = ScreenshotEditorController()

    private var window: NSWindow?
    private var editor: ScreenshotEditorView?
    private var keyMonitor: Any?

    private let toolbar = NSView(frame: .zero)
    private var toolButtons: [NSButton] = []
    private var actionButtons: [NSButton] = []
    private var colorButtons: [NSButton] = []
    private var separators: [NSView] = []
    /// 文字字号下拉框（只在选中文字工具时出现）
    private let fontSizeControl = NSPopUpButton(frame: .zero, pullsDown: false)

    private static let toolbarHeight: CGFloat = 46

    @discardableResult
    func start() -> Bool {
        guard window == nil else { return true }
        guard let screen = NSScreen.main, let image = ScreenCapture.screenImage() else { return false }

        let view = ScreenshotEditorView(frame: screen.frame)
        view.backgroundImage = image
        let win = ScreenshotWindow(contentRect: screen.frame,
                                   styleMask: .borderless,
                                   backing: .buffered,
                                   defer: false)
        win.level = .screenSaver
        // 不透明窗口：整屏定格画面绘制后，底下实时屏幕完全不会透出
        win.isOpaque = true
        win.backgroundColor = .black
        win.ignoresMouseEvents = false
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.contentView = view

        view.onSelectionDone = { [weak self] in self?.showToolbar() }
        view.onCancel = { [weak self] in self?.close() }
        view.onChange = { [weak self] in self?.updateToolbar() }
        view.onConfirm = { [weak self] in self?.copyAndClose() }

        buildToolbar()
        window = win
        editor = view
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        win.display()
        view.needsDisplay = true
        win.makeFirstResponder(view)
        installKeyMonitor()

        return true
    }

    // MARK: - Esc 取消

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window != nil else { return event }
            guard event.keyCode == 53 else { return event }
            // 正在输入文字时，第一下 Esc 结束输入，再按一次才取消截图
            if self.editor?.commitTextIfEditing() == true { return nil }
            self.close()
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - 工具栏

    private func buildToolbar() {
        toolbar.subviews.forEach { $0.removeFromSuperview() }
        toolButtons.removeAll()
        actionButtons.removeAll()
        colorButtons.removeAll()
        separators.removeAll()

        toolbar.wantsLayer = true
        toolbar.appearance = NSAppearance(named: .darkAqua)
        toolbar.layer?.cornerRadius = 12
        toolbar.layer?.borderWidth = 1
        toolbar.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        toolbar.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.95).cgColor
        toolbar.isHidden = true

        for (index, color) in ScreenshotEditorView.palette.enumerated() {
            let button = NSButton(frame: .zero)
            button.title = ""
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 7.5
            button.layer?.backgroundColor = color.cgColor
            button.layer?.borderWidth = 2
            button.layer?.borderColor = NSColor.clear.cgColor
            button.target = self
            button.action = #selector(chooseColor(_:))
            button.tag = 100 + index
            button.toolTip = "标注颜色"
            colorButtons.append(button)
        }

        // 与系统截图一致：颜色 / 矩形·椭圆·画笔·箭头·马赛克·文字 / 撤销·保存 / 取消·完成
        let toolSpecs: [(ScreenshotEditorView.Tool, [String], String)] = [
            (.rectangle, ["rectangle"], "矩形"),
            (.ellipse, ["circle"], "椭圆"),
            (.pen, ["pencil"], "画笔"),
            (.arrow, ["arrow.up.right", "arrow.right"], "箭头"),
            (.mosaic, ["square.grid.3x3", "square.dashed"], "马赛克：按住鼠标涂抹"),
            (.text, ["t.square", "textformat"], "文字")
        ]
        for (tool, symbols, tip) in toolSpecs {
            let button = makeIconButton(symbols: symbols, tooltip: tip, action: #selector(chooseTool(_:)))
            button.tag = 10 + tool.rawValue
            toolButtons.append(button)
        }

        let undo = makeIconButton(symbols: ["arrow.uturn.backward"], tooltip: "撤销上一个标注", action: #selector(undo))
        let download = makeIconButton(symbols: ["square.and.arrow.down"], tooltip: "保存截图", action: #selector(saveAndClose))
        let cancel = makeIconButton(symbols: ["xmark"], tooltip: "取消截图（Esc）", action: #selector(close), tint: .systemRed)
        let done = makeIconButton(symbols: ["checkmark"], tooltip: "完成并复制到剪贴板", action: #selector(copyAndClose), tint: .systemGreen)
        actionButtons = [undo, download, cancel, done]

        fontSizeControl.removeAllItems()
        for size in ScreenshotEditorView.fontSizeOptions {
            fontSizeControl.addItem(withTitle: "\(Int(size))pt")
        }
        fontSizeControl.target = self
        fontSizeControl.action = #selector(chooseFontSize(_:))
        fontSizeControl.controlSize = .small
        fontSizeControl.font = NSFont.systemFont(ofSize: 11)
        fontSizeControl.appearance = NSAppearance(named: .darkAqua)
        fontSizeControl.toolTip = "文字字号"
        fontSizeControl.isHidden = true

        for _ in 0..<3 {
            let line = NSView(frame: .zero)
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            separators.append(line)
        }

        colorButtons.forEach { toolbar.addSubview($0) }
        toolButtons.forEach { toolbar.addSubview($0) }
        toolbar.addSubview(fontSizeControl)
        actionButtons.forEach { toolbar.addSubview($0) }
        separators.forEach { toolbar.addSubview($0) }

        layoutToolbar()
        updateToolbar()
    }

    private func makeIconButton(symbols: [String], tooltip: String, action: Selector,
                                tint: NSColor = .white) -> NSButton {
        let button = NSButton(frame: .zero)
        button.title = ""
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        if let image = symbolImage(symbols) {
            button.image = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
        }
        button.contentTintColor = tint
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        return button
    }

    private func symbolImage(_ names: [String]) -> NSImage? {
        if #available(macOS 11.0, *) {
            for name in names {
                if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
                    return image
                }
            }
        }
        return nil
    }

    private func layoutToolbar() {
        let height = Self.toolbarHeight
        var x: CGFloat = 10
        var separatorCursor = 0
        func placeSeparator(height: CGFloat, spacingBefore: CGFloat = 2, spacingAfter: CGFloat = 6) {
            guard separatorCursor < separators.count else { return }
            let line = separators[separatorCursor]
            separatorCursor += 1
            x += spacingBefore
            line.frame = NSRect(x: x, y: (height - 20) / 2, width: 1, height: 20)
            x += 1 + spacingAfter
        }

        func placeIconButtons(_ buttons: [NSButton]) {
            for button in buttons {
                button.frame = NSRect(x: x, y: (height - 32) / 2, width: 32, height: 32)
                x += 34
            }
        }

        for button in colorButtons {
            button.frame = NSRect(x: x, y: (height - 15) / 2, width: 15, height: 15)
            x += 20
        }
        placeSeparator(height: height)
        placeIconButtons(toolButtons)
        if !fontSizeControl.isHidden {
            x += 2
            fontSizeControl.frame = NSRect(x: x, y: (height - 22) / 2, width: 66, height: 22)
            x += 66 + 2
        }
        placeSeparator(height: height)
        placeIconButtons(Array(actionButtons.prefix(2)))   // 撤销、保存
        placeSeparator(height: height)
        placeIconButtons(Array(actionButtons.suffix(2)))    // 取消、完成
        x += 6
        toolbar.frame = NSRect(x: toolbar.frame.origin.x, y: toolbar.frame.origin.y,
                               width: x, height: height)
    }

    /// 工具栏宽度会随字号控件出现/隐藏而变化，重排后保持居中
    private func layoutToolbarKeepingCenter() {
        let midX = toolbar.frame.midX
        layoutToolbar()
        guard let container = toolbar.superview, !toolbar.isHidden else { return }
        let margin: CGFloat = 10
        let x = max(margin, min(midX - toolbar.frame.width / 2,
                                container.bounds.width - toolbar.frame.width - margin))
        toolbar.frame.origin.x = x
    }

    private func showToolbar() {
        guard let editor, let window else { return }
        let bounds = window.contentView?.bounds ?? editor.bounds
        let selection = editor.selectionRect
        let gap: CGFloat = 12
        let margin: CGFloat = 10

        // 默认贴在选区正下方，方便顺手点；下方放不下时翻到选区上方
        var x = selection.midX - toolbar.frame.width / 2
        var y = selection.minY - toolbar.frame.height - gap
        if y < margin {
            y = min(bounds.height - toolbar.frame.height - margin, selection.maxY + gap)
        }
        x = max(margin, min(x, bounds.width - toolbar.frame.width - margin))
        toolbar.frame.origin = NSPoint(x: x, y: y)
        toolbar.isHidden = false
        if toolbar.superview !== editor {
            editor.addSubview(toolbar)
        }
        editor.commitPendingText()
        window.makeFirstResponder(editor)
        updateToolbar()
    }

    private func hideToolbar() {
        toolbar.isHidden = true
    }

    private func updateToolbar() {
        guard let editor else { return }
        let activeTag = 10 + editor.activeTool.rawValue
        for button in toolButtons {
            button.layer?.backgroundColor = button.tag == activeTag
                ? NSColor.white.withAlphaComponent(0.18).cgColor
                : NSColor.clear.cgColor
        }
        for button in colorButtons {
            button.layer?.borderColor = button.tag - 100 == editor.activeColorIndex
                ? NSColor.white.cgColor
                : NSColor.clear.cgColor
        }

        // 字号只在文字工具下出现，出现/隐藏时重排并保持居中
        let showsFont = editor.activeTool == .text
        if fontSizeControl.isHidden != !showsFont {
            fontSizeControl.isHidden = !showsFont
            layoutToolbarKeepingCenter()
        }
        let title = "\(Int(editor.activeFontSize))pt"
        if fontSizeControl.titleOfSelectedItem != title {
            fontSizeControl.selectItem(withTitle: title)
        }

        actionButtons.first?.isEnabled = editor.hasAnnotations
    }

    // MARK: - 工具与颜色

    @objc private func chooseTool(_ sender: NSButton) {
        guard let tool = ScreenshotEditorView.Tool(rawValue: sender.tag - 10) else { return }
        editor?.commitPendingText()
        editor?.activeTool = tool
        updateToolbar()
        window?.makeFirstResponder(editor)
    }

    @objc private func chooseColor(_ sender: NSButton) {
        // 颜色同时作用于矩形、椭圆、画笔与文字
        editor?.commitPendingText()
        editor?.activeColorIndex = sender.tag - 100
        updateToolbar()
        window?.makeFirstResponder(editor)
    }

    @objc private func chooseFontSize(_ sender: NSPopUpButton) {
        guard let editor else { return }
        editor.commitPendingText()
        let options = ScreenshotEditorView.fontSizeOptions
        let index = min(max(sender.indexOfSelectedItem, 0), options.count - 1)
        editor.activeFontSize = options[index]
        updateToolbar()
        window?.makeFirstResponder(editor)
    }

    // MARK: - 操作

    @objc private func undo() {
        editor?.undoLast()
        updateToolbar()
    }

    @objc private func copyAndClose() {
        editor?.commitPendingText()
        guard let image = editor?.resultImage() else { close(); return }
        ScreenCapture.copyToPasteboard(image)
        close()
    }

    @objc private func saveAndClose() {
        editor?.commitPendingText()
        guard let image = editor?.resultImage() else { close(); return }
        if let url = ScreenCapture.saveScreenshot(image) {
            NotificationCenter.default.post(name: .xspaceScreenshotSaved, object: url)
        }
        close()
    }

    @objc private func close() {
        removeKeyMonitor()
        editor?.commitPendingText()
        window?.makeFirstResponder(nil)
        window?.orderOut(nil)
        toolbar.removeFromSuperview()
        toolbar.isHidden = true
        window = nil
        editor = nil
    }
}

enum HashKind: String, CaseIterable {
    case md5 = "MD5"
    case sha1 = "SHA-1"
    case sha256 = "SHA-256"
    case sha512 = "SHA-512"
}

enum HashComputer {
    /// 流式计算文件哈希，避免大文件一次性载入内存。
    static func hash(_ url: URL, kind: HashKind) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        let chunkSize = 1024 * 1024
        switch kind {
        case .md5:
            var hasher = Insecure.MD5()
            while true {
                let chunk = handle.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return hex(hasher.finalize())
        case .sha1:
            var hasher = Insecure.SHA1()
            while true {
                let chunk = handle.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return hex(hasher.finalize())
        case .sha256:
            var hasher = SHA256()
            while true {
                let chunk = handle.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return hex(hasher.finalize())
        case .sha512:
            var hasher = SHA512()
            while true {
                let chunk = handle.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return hex(hasher.finalize())
        }
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum Symbol {
    static func image(_ name: String, fallback: String? = nil) -> NSImage? {
        if #available(macOS 11.0, *) {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
                return image
            }
        }
        if let fallback { return NSImage(named: fallback) }
        return nil
    }
}

enum WallpaperRenderer {
    // 使用线程安全的 NSCache：全局/窗格壁纸可能由主线程与通知回调并发触发渲染，
    // 普通 Swift Dictionary 的并发读写会产生数据竞争导致崩溃。
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 8   // 拖动改变窗口大小时尺寸频繁变化，只保留少量最近结果
        return cache
    }()
    private static let baseCache = NSCache<NSString, NSImage>()

    /// 按指定尺寸与填充模式渲染壁纸；返回图像已包含透明通道，直接绘制即可。
    static func image(path: String?, blur: Int, mode: WallpaperFillMode, size: NSSize) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let key = "\(path)#\(blur)#\(mode.rawValue)#\(width)x\(height)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = baseImage(path: path, blur: blur) else { return nil }

        let targetSize = NSSize(width: width, height: height)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: width,
                                         pixelsHigh: height,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        rep.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: targetSize)).fill()

        switch mode {
        case .stretch:
            source.draw(in: NSRect(origin: .zero, size: targetSize))
        case .tile:
            let tileSize = source.size
            if tileSize.width > 0, tileSize.height > 0 {
                var y: CGFloat = 0
                while y < targetSize.height {
                    var x: CGFloat = 0
                    while x < targetSize.width {
                        source.draw(in: NSRect(x: x, y: y, width: tileSize.width, height: tileSize.height))
                        x += tileSize.width
                    }
                    y += tileSize.height
                }
            }
        case .center:
            // 原始大小居中，超出部分裁掉
            let size = source.size
            let rect = NSRect(x: (targetSize.width - size.width) / 2,
                              y: (targetSize.height - size.height) / 2,
                              width: size.width,
                              height: size.height)
            source.draw(in: rect)
        case .fill:
            // 等比放大到铺满，超出部分裁掉（aspect fill）
            let size = source.size
            guard size.width > 0, size.height > 0 else { break }
            let scale = max(targetSize.width / size.width, targetSize.height / size.height)
            let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
            let rect = NSRect(x: (targetSize.width - drawSize.width) / 2,
                              y: (targetSize.height - drawSize.height) / 2,
                              width: drawSize.width,
                              height: drawSize.height)
            source.draw(in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: targetSize)
        image.addRepresentation(rep)
        cache.setObject(image, forKey: key)
        return image
    }

    private static func baseImage(path: String, blur: Int) -> NSImage? {
        let key = "\(path)#\(blur)" as NSString
        if let cached = baseCache.object(forKey: key) { return cached }
        let url = URL(fileURLWithPath: path)
        guard let original = NSImage(contentsOf: url) else { return nil }
        guard blur > 1 else {
            baseCache.setObject(original, forKey: key)
            return original
        }
        let fallbackCI = original.cgImage(forProposedRect: nil, context: nil, hints: nil).map { CIImage(cgImage: $0) }
        guard let ciImage = CIImage(contentsOf: url) ?? fallbackCI else {
            baseCache.setObject(original, forKey: key)
            return original
        }
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CGFloat(blur) / 10.0, forKey: kCIInputRadiusKey)
        guard let output = filter?.outputImage else {
            baseCache.setObject(original, forKey: key)
            return original
        }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        baseCache.setObject(image, forKey: key)
        return image
    }
}

enum Dialog {
    static func alert(title: String, message: String, window: NSWindow? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        if let window {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }

    static func confirm(title: String, message: String, confirmTitle: String = "确定", window: NSWindow? = nil) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func textInput(title: String, message: String, defaultValue: String = "", confirmTitle: String = "确定", window: NSWindow?) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        // 提前建好弹窗并把输入框设为初始焦点，保证打开就能直接打字、按 Delete 删字
        alert.layout()
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 文件同名冲突：替换 / 改名 / 取消 三选一
    static func chooseConflict(fileName: String, existingName: String) -> ConflictChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "目标位置已存在同名文件"
        alert.informativeText = "「\(fileName)」与现有的「\(existingName)」内容不同。\n\n"
            + "替换：用新文件覆盖现有文件\n"
            + "改名：自动在文件名后加编号（保留两份）\n"
            + "取消：跳过此文件，不做改动"
        alert.addButton(withTitle: "替换")
        alert.addButton(withTitle: "改名")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .replace
        case .alertSecondButtonReturn: return .rename
        default: return .cancel
        }
    }
}

/// 移动文件遇到同名冲突时用户的选择
enum ConflictChoice {
    case replace
    case rename
    case cancel
}

enum ShellPath {
    /// 转成可以直接粘贴到终端的 bash 路径：
    /// 没有空格等特殊字符时原样输出，含空格/引号等字符时用单引号包裹（单引号内部按 `'\''` 转义）。
    static func bashQuoted(_ path: String) -> String {
        guard !path.isEmpty else { return "''" }
        let needsQuote = path.contains { character in
            " \t\n'\"$&|;<>()*?[]{}!#~`\\".contains(character)
        }
        guard needsQuote else { return path }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension ShellPath {
    /// 把 bash 转义过的路径还原成真实路径（用于粘贴回来直接回车跳转）
    static func unescape(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") {
            value = String(value.dropFirst().dropLast())
            value = value.replacingOccurrences(of: "'\\''", with: "'")
        } else if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }
}

enum FileOperations {
    static func uniqueURL(for url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    // MARK: - 同名冲突处理

    /// 单个移动项的冲突决策结果
    private enum ConflictResolution {
        case identical          // 内容一致：删掉来源，保留目标那一份
        case replaceExisting    // 用户选“替换”：删目标再移动
        case useDestination(URL)// 用户选“改名”：移动到带编号的新路径
        case skip               // 取消 / 无需处理
    }

    /// 判断移动 `source` 到 `destination` 时该如何处理同名冲突。
    /// 只比较普通文件；目录、无法读取的文件一律交给用户决定。
    private static func resolveMoveConflict(source: URL, destination: URL) -> ConflictResolution {
        // 同一路径（例如拖回当前目录）：什么都不做，避免误删自己
        if source.standardizedFileURL.path == destination.standardizedFileURL.path { return .skip }

        let fm = FileManager.default
        var sourceIsDir: ObjCBool = false
        var destIsDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &sourceIsDir),
              fm.fileExists(atPath: destination.path, isDirectory: &destIsDir) else {
            return .skip
        }

        // 目录没有单一的文件内容哈希；直接用大小/结构也不可靠，交由用户决定
        if sourceIsDir.boolValue || destIsDir.boolValue {
            return askConflict(source: source, destination: destination)
        }

        // 先用文件大小快速排除：大小不同则内容必然不同，省去大文件哈希计算
        let sSize = try? fm.attributesOfItem(atPath: source.path)[.size] as? NSNumber
        let dSize = try? fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber
        if sSize != nil, dSize != nil, sSize != dSize {
            return askConflict(source: source, destination: destination)
        }

        // 大小相同再用 SHA-256 流式比对，避免大文件一次性载入内存
        if let sHash = try? HashComputer.hash(source, kind: .sha256),
           let dHash = try? HashComputer.hash(destination, kind: .sha256),
           sHash == dHash {
            return .identical
        }
        return askConflict(source: source, destination: destination)
    }

    private static func askConflict(source: URL, destination: URL) -> ConflictResolution {
        switch Dialog.chooseConflict(fileName: source.lastPathComponent,
                                     existingName: destination.lastPathComponent) {
        case .replace: return .replaceExisting
        case .rename:  return .useDestination(uniqueURL(for: destination))
        case .cancel:  return .skip
        }
    }

    /// 源文件位于只读卷（挂载的 DMG、光盘等）时无法移动，自动按复制处理。
    static func isOnReadOnlyVolume(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly) == true
    }

    static func copyItems(_ urls: [URL], into directory: URL, move: Bool = false, replace: Bool = false) -> [URL] {
        // 只读卷上的文件不能移动，整批降级为复制，避免“操作不允许”报错
        let effectiveMove = move && !urls.contains { isOnReadOnlyVolume($0) }
        var results: [URL] = []
        var pairs: [(source: URL, destination: URL)] = []
        // 内容一致被删掉的来源：撤销时需要从保留的那一份再复制回来
        var identicalDedup: [(source: URL, kept: URL)] = []
        for url in urls {
            let desired = directory.appendingPathComponent(url.lastPathComponent)
            var destination = desired
            var deduplicate = false
            var skip = false
            var overwrite = replace // 外部显式要求替换时保持原行为

            if effectiveMove && !replace && FileManager.default.fileExists(atPath: desired.path) {
                // 移动且目标已有同名：走冲突决策（哈希对比 / 三选一）
                switch resolveMoveConflict(source: url, destination: desired) {
                case .identical:
                    deduplicate = true
                case .replaceExisting:
                    overwrite = true // 删掉已有目标，再移动过来
                case .useDestination(let unique):
                    destination = unique
                case .skip:
                    skip = true
                }
            } else if !replace {
                destination = uniqueURL(for: destination)
            }
            if skip { continue }

            do {
                if deduplicate {
                    // 内容完全一致：删掉来源，只保留目标已有的那一份
                    try FileManager.default.removeItem(at: url)
                    identicalDedup.append((url, desired))
                    results.append(desired)
                } else {
                    if FileManager.default.fileExists(atPath: destination.path) && overwrite {
                        try FileManager.default.removeItem(at: destination)
                    }
                    if effectiveMove {
                        try FileManager.default.moveItem(at: url, to: destination)
                    } else {
                        try FileManager.default.copyItem(at: url, to: destination)
                    }
                    results.append(destination)
                    pairs.append((url, destination))
                }
            } catch {
                Dialog.alert(title: "操作失败", message: "\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        let total = pairs.count + identicalDedup.count
        if total > 0 {
            let verb = effectiveMove ? "移动" : "复制"
            FileUndoStack.shared.record("\(verb) \(total) 个项目") {
                for pair in pairs.reversed() {
                    if effectiveMove {
                        _ = UndoIO.move(pair.destination, to: pair.source)
                    } else {
                        _ = UndoIO.remove(pair.destination)
                    }
                }
                // 哈希一致而被删除的来源：从保留的目标复制回去，恢复原状
                for pair in identicalDedup.reversed() {
                    guard !FileManager.default.fileExists(atPath: pair.source.path),
                          FileManager.default.fileExists(atPath: pair.kept.path) else { continue }
                    try? FileManager.default.copyItem(at: pair.kept, to: pair.source)
                }
            }
        }
        return results
    }

    static func trashItems(_ urls: [URL]) {
        var failures: [String] = []
        var pairs: [(trashed: URL, source: URL)] = []
        for url in urls {
            do {
                if #available(macOS 10.15, *) {
                    var resulting: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                    if let trashed = resulting as URL? { pairs.append((trashed, url)) }
                } else {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            Dialog.alert(title: "无法移到废纸篓", message: failures.joined(separator: "\n"))
        }
        if !pairs.isEmpty {
            FileUndoStack.shared.record("移到废纸篓 \(pairs.count) 个项目") {
                for pair in pairs.reversed() {
                    _ = UndoIO.move(pair.trashed, to: pair.source)
                }
            }
        }
    }

    static func createFolder(in directory: URL, named name: String) -> URL? {
        let url = uniqueURL(for: directory.appendingPathComponent(name))
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            FileUndoStack.shared.record("新建文件夹") {
                _ = UndoIO.remove(url)
            }
            return url
        } catch {
            Dialog.alert(title: "无法新建文件夹", message: error.localizedDescription)
            return nil
        }
    }

    static func openInTerminal(_ url: URL) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            Dialog.alert(title: "无法打开终端", message: "找不到终端应用")
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

/// Finder 原生格式的拖放项：完整转发 NSURL 写入的所有类型（public.file-url、
/// NSFilenamesPboardType、Apple URL pasteboard type 及 dyn.* 别名类型），不额外写入
/// 纯文本类型。Electron/Chromium 应用（极空间、百度网盘等）依赖别名类型识别文件，
/// 若混入 public.utf8-plain-text 会优先按文本处理而拒绝；IINA 等播放器读取
/// NSFilenamesPboardType，原生格式同样包含。可附加自定义标记供内部拖放识别。
final class FinderDragItem: NSObject, NSPasteboardWriting {
    private let url: URL
    private let marker: (type: NSPasteboard.PasteboardType, value: String)?

    init(_ url: URL, marker: (type: NSPasteboard.PasteboardType, value: String)? = nil) {
        self.url = url
        self.marker = marker
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = (url as NSURL).writableTypes(for: pasteboard)
        if let marker, !types.contains(marker.type) {
            types.append(marker.type)
        }
        return types
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if let marker, type == marker.type { return marker.value }
        return (url as NSURL).pasteboardPropertyList(forType: type)
    }
}

extension URL {
    /// Finder 兼容的拖放项，保留 NSURL 原生写入的全套类型。
    var dragPasteboardItem: FinderDragItem { FinderDragItem(self) }
}

extension Array where Element == URL {
    var pasteboardObjects: [NSPasteboardWriting] { map { $0.dragPasteboardItem } }
}
