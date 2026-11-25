import AppKit

/// 自绘的「显示简介」窗口：顶部图标/名称/大小/修改时间 + 复制绝对路径按钮，
/// 下方为通用信息（种类、大小、位置、创建时间、修改时间）。
final class FileInfoWindowController: NSWindowController, NSWindowDelegate {
    private static var openWindows: [FileInfoWindowController] = []

    private let url: URL
    private let copyButton = NSButton(title: "复制路径", target: nil, action: nil)

    init(url: URL) {
        self.url = url
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 372),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "简介"
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func show(for url: URL) {
        let controller = FileInfoWindowController(url: url)
        openWindows.append(controller)
        // 定位到当前窗口所在屏幕的正中央（多屏时跟随当前工作屏幕）
        if let window = controller.window {
            let screen = NSApp.keyWindow?.screen ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2,
                                              y: visible.midY - window.frame.height / 2))
            } else {
                window.center()
            }
        }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        Self.openWindows.removeAll { $0 === self }
    }

    private func buildUI() {
        guard let root = window?.contentView else { return }
        let item = FileItem(url: url)
        let creation = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate

        // 顶部：大图标 + 名称 + 大小 + 修改时间
        let icon = NSImageView(frame: NSRect(x: 22, y: 282, width: 64, height: 64))
        icon.image = item.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        root.addSubview(icon)

        let name = NSTextField(labelWithString: item.displayName)
        name.frame = NSRect(x: 98, y: 314, width: 250, height: 22)
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.lineBreakMode = .byTruncatingMiddle
        root.addSubview(name)

        let sizeText = NSTextField(labelWithString: FileSizeFormatter.string(item.size))
        sizeText.frame = NSRect(x: 98, y: 290, width: 250, height: 18)
        sizeText.font = .systemFont(ofSize: 12)
        sizeText.textColor = .secondaryLabelColor
        root.addSubview(sizeText)

        let dateText = NSTextField(labelWithString: "修改时间：\(item.modified.map { DateFormatterStore.medium.string(from: $0) } ?? "未知")")
        dateText.frame = NSRect(x: 98, y: 270, width: 250, height: 18)
        dateText.font = .systemFont(ofSize: 11)
        dateText.textColor = .secondaryLabelColor
        dateText.lineBreakMode = .byTruncatingMiddle
        root.addSubview(dateText)

        // 右上角：复制绝对路径按钮
        copyButton.frame = NSRect(x: 356, y: 306, width: 84, height: 26)
        copyButton.bezelStyle = .rounded
        copyButton.font = .systemFont(ofSize: 11)
        copyButton.target = self
        copyButton.action = #selector(copyAbsolutePath(_:))
        root.addSubview(copyButton)

        addSeparator(y: 254, in: root)

        let section = NSTextField(labelWithString: "通用：")
        section.frame = NSRect(x: 24, y: 230, width: 100, height: 20)
        section.font = .systemFont(ofSize: 12, weight: .semibold)
        root.addSubview(section)

        let byteText = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
        var rows: [(String, String)] = [
            ("种类：", item.kind),
            ("大小：", "\(byteText)（\(item.size) 字节）"),
            ("位置：", url.deletingLastPathComponent().path),
            ("修改时间：", item.modified.map { DateFormatterStore.medium.string(from: $0) } ?? "未知"),
        ]
        if let creation {
            rows.insert(("创建时间：", DateFormatterStore.medium.string(from: creation)), at: 3)
        }

        var y: CGFloat = 204
        for (label, value) in rows {
            let key = NSTextField(labelWithString: label)
            key.frame = NSRect(x: 44, y: y, width: 76, height: 20)
            key.font = .systemFont(ofSize: 12)
            key.alignment = .right
            key.textColor = .secondaryLabelColor
            root.addSubview(key)

            let val = NSTextField(labelWithString: value)
            val.frame = NSRect(x: 126, y: y, width: 312, height: 20)
            val.font = .systemFont(ofSize: 12)
            val.lineBreakMode = .byTruncatingMiddle
            val.toolTip = value
            root.addSubview(val)
            y -= 26
        }
    }

    private func addSeparator(y: CGFloat, in root: NSView) {
        let line = NSView(frame: NSRect(x: 22, y: y, width: 416, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        root.addSubview(line)
    }

    @objc private func copyAbsolutePath(_ sender: Any) {
        let path = url.path
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        copyButton.title = "已复制"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.title = "复制路径"
        }
    }
}
