import AppKit

/// 轻量悬停提示气泡：鼠标停在工具栏按钮上约 0.25 秒后在按钮下方显示简短说明
final class TooltipOverlay {
    static let shared = TooltipOverlay()

    private let panel = NSPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let label = NSTextField(labelWithString: "")
    private var pending: DispatchWorkItem?

    private init() {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.92).cgColor
        container.layer?.cornerRadius = 6
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.14).cgColor

        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .white
        label.isBezeled = false
        label.drawsBackground = false
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.cell?.wraps = false
        label.cell?.isScrollable = false
        container.addSubview(label)
        panel.contentView = container
    }

    func show(_ text: String?, for anchor: NSView) {
        guard let text, !text.isEmpty else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self, weak anchor] in
            guard let self, let anchor, let window = anchor.window else { return }
            self.present(text, for: anchor, in: window)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func hide() {
        pending?.cancel()
        pending = nil
        panel.orderOut(nil)
    }

    private func present(_ text: String, for anchor: NSView, in window: NSWindow) {
        let maxTextSize = NSSize(width: 240, height: 40)
        let textSize = (text as NSString).boundingRect(
            with: maxTextSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: label.font ?? NSFont.systemFont(ofSize: 12)]
        ).integral
        let textWidth = ceil(textSize.width) + 4
        let width = textWidth + 20
        let height = ceil(textSize.height) + 12

        guard let container = panel.contentView else { return }
        container.frame = NSRect(x: 0, y: 0, width: width, height: height)
        label.frame = NSRect(x: 10, y: 6, width: textWidth, height: ceil(textSize.height))
        label.stringValue = text

        let anchorRect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        var x = anchorRect.midX - width / 2
        x = max(screen.minX + 4, min(x, screen.maxX - width - 4))
        var y = anchorRect.minY - height - 6
        if y < screen.minY + 4 { y = anchorRect.maxY + 6 }
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }
}

/// 带悬停提示的按钮：统一给工具栏按钮使用，替代系统 toolTip（不依赖系统提示延迟）
class TooltipButton: NSButton {
    var tooltipText: String?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        TooltipOverlay.shared.show(tooltipText ?? toolTip, for: self)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        TooltipOverlay.shared.hide()
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        TooltipOverlay.shared.hide()
        super.mouseDown(with: event)
    }
}
