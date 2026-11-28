import Foundation
import AppKit

/// 偏好设置中的「输入法」页：全局锁定某个输入法。
final class InputSourceSettingsView: NSView {
    private let enableBox = NSButton(checkboxWithTitle: "启用输入法锁定", target: nil, action: nil)
    private let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshButton = NSButton(title: "刷新列表", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private var isReloading = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
        reloadSources()
        refreshStatus()
        NotificationCenter.default.addObserver(
            self, selector: #selector(stateChanged),
            name: .xspaceInputSourceChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(listChanged),
            name: .xspaceInputSourceListChanged, object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func buildUI() {
        addSubview(SettingCardView(frame: NSRect(x: 16, y: 362, width: 528, height: 134)))
        let title = label("输入法锁定", frame: NSRect(x: 34, y: 470, width: 200, height: 20))
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        addSubview(title)

        enableBox.frame = NSRect(x: 34, y: 438, width: 230, height: 22)
        enableBox.font = NSFont.systemFont(ofSize: 12)
        enableBox.target = self
        enableBox.action = #selector(toggleEnabled)
        addSubview(enableBox)

        let intro = label(
            "开启后，系统输入法一旦被切走会自动切回指定输入法；密码框等安全输入期间自动避让。",
            frame: NSRect(x: 34, y: 396, width: 488, height: 34)
        )
        intro.font = NSFont.systemFont(ofSize: 11)
        intro.textColor = .secondaryLabelColor
        intro.lineBreakMode = .byWordWrapping
        addSubview(intro)

        addSubview(SettingCardView(frame: NSRect(x: 16, y: 224, width: 528, height: 122)))
        let targetTitle = label("锁定目标", frame: NSRect(x: 34, y: 320, width: 200, height: 20))
        targetTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        addSubview(targetTitle)

        sourcePopup.frame = NSRect(x: 34, y: 282, width: 344, height: 26)
        sourcePopup.font = NSFont.systemFont(ofSize: 12)
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceChanged)
        addSubview(sourcePopup)

        refreshButton.frame = NSRect(x: 388, y: 282, width: 132, height: 26)
        refreshButton.bezelStyle = .rounded
        refreshButton.font = NSFont.systemFont(ofSize: 11)
        refreshButton.target = self
        refreshButton.action = #selector(refreshSources)
        addSubview(refreshButton)

        statusLabel.frame = NSRect(x: 34, y: 244, width: 486, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        addSubview(statusLabel)

        addSubview(SettingCardView(frame: NSRect(x: 16, y: 44, width: 528, height: 164)))
        let creditTitle = label("实现说明", frame: NSRect(x: 34, y: 182, width: 200, height: 20))
        creditTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        addSubview(creditTitle)

        let note = label(
            "输入法监听与自动切回的思路参考 oomol-lab/LockIME（GPL-3.0），XSpace 未复制其源码，\n而是用系统 Text Input Services API 独立实现。中文输入法会优先让当前键盘焦点进程自行切换，\n失败时回退到 TISSelectInputSource；连续被其它程序抢走时会短暂退让，避免反复抢占。",
            frame: NSRect(x: 34, y: 90, width: 486, height: 82)
        )
        note.font = NSFont.systemFont(ofSize: 10)
        note.textColor = .tertiaryLabelColor
        note.lineBreakMode = .byWordWrapping
        addSubview(note)
    }

    private func label(_ title: String, frame: NSRect) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.frame = frame
        field.font = NSFont.systemFont(ofSize: 12)
        field.textColor = .labelColor
        field.isEditable = false
        field.isSelectable = false
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        InputSourceLock.shared.setEnabled(sender.state == .on)
        refreshStatus()
    }

    @objc private func sourceChanged(_ sender: NSPopUpButton) {
        guard !isReloading else { return }
        let id = sender.selectedItem?.representedObject as? String
        InputSourceLock.shared.choose(id)
        refreshStatus()
    }

    @objc private func refreshSources() {
        reloadSources()
        refreshStatus()
    }

    @objc private func stateChanged() {
        refreshStatus()
    }

    @objc private func listChanged() {
        reloadSources()
        refreshStatus()
    }

    private func reloadSources() {
        isReloading = true
        defer { isReloading = false }
        let sources = InputSourceLock.shared.availableSources()
        let currentTarget = InputSourceLock.shared.targetID
        sourcePopup.removeAllItems()
        sourcePopup.addItem(withTitle: "不锁定（仅开启时生效）")
        sourcePopup.item(at: 0)?.representedObject = nil

        for source in sources {
            sourcePopup.addItem(withTitle: source.name)
            sourcePopup.lastItem?.representedObject = source.id
        }
        if let currentTarget, !sources.contains(where: { $0.id == currentTarget }) {
            sourcePopup.addItem(withTitle: "\(currentTarget)（不可用）")
            sourcePopup.lastItem?.representedObject = currentTarget
        }
        if let currentTarget,
           let index = (0..<sourcePopup.numberOfItems).first(where: {
               sourcePopup.item(at: $0)?.representedObject as? String == currentTarget
           }) {
            sourcePopup.selectItem(at: index)
        } else {
            sourcePopup.selectItem(at: 0)
        }
    }

    private func refreshStatus() {
        enableBox.state = InputSourceLock.shared.isEnabled ? .on : .off
        let target = InputSourceLock.shared.targetName ?? "未选择"
        statusLabel.stringValue = "\(InputSourceLock.shared.statusSummary) · 当前系统输入法：\(InputSourceLock.shared.currentName()) · 目标：\(target)"
    }
}
