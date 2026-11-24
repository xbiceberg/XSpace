import AppKit

// MARK: - 单个规则的配置面板

/// 根据规则类型生成对应的配置表单（左侧「添加规则」列表右侧的面板）
final class RuleConfigView: NSView {
    private var rule: RenameRule
    private let stack = NSStackView()
    private var controls: [String: NSControl] = [:]
    private var textViews: [String: NSTextView] = [:]
    private var radioValues: [String: Int] = [:]

    init(rule: RenameRule) {
        self.rule = rule
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 430))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6)
        ])
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 控件工厂

    private func label(_ text: String, width: CGFloat = 78) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        field.font = NSFont.systemFont(ofSize: 12)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    private func hint(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func textField(_ key: String, _ value: String, width: CGFloat = 280) -> NSTextField {
        let field = NSTextField(string: value)
        field.font = NSFont.systemFont(ofSize: 12)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        controls[key] = field
        return field
    }

    private func intField(_ key: String, _ value: Int, width: CGFloat = 64) -> NSTextField {
        let field = NSTextField(string: "\(value)")
        field.font = NSFont.systemFont(ofSize: 12)
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        controls[key] = field
        return field
    }

    private func checkbox(_ key: String, _ title: String, _ on: Bool) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.font = NSFont.systemFont(ofSize: 12)
        button.state = on ? .on : .off
        controls[key] = button
        return button
    }

    private func radioRow(_ key: String, _ titles: [String], _ selected: Int) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        // 不让单选组把整行撑开，后面的输入框才能紧跟着排列
        row.setContentHuggingPriority(.required, for: .horizontal)
        row.setContentCompressionResistancePriority(.required, for: .horizontal)
        radioValues[key] = selected
        for (index, title) in titles.enumerated() {
            let button = NSButton(radioButtonWithTitle: title, target: self, action: #selector(radioChanged(_:)))
            button.font = NSFont.systemFont(ofSize: 12)
            button.tag = index
            button.identifier = NSUserInterfaceItemIdentifier(key)
            button.state = index == selected ? .on : .off
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            row.addArrangedSubview(button)
        }
        return row
    }

    private func popup(_ key: String, _ items: [String], _ selected: Int) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.font = NSFont.systemFont(ofSize: 12)
        button.addItems(withTitles: items)
        button.selectItem(at: min(max(0, selected), max(0, items.count - 1)))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 190).isActive = true
        controls[key] = button
        return button
    }

    @objc private func radioChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        radioValues[key] = sender.tag
        if let row = sender.superview {
            for case let button as NSButton in row.subviews
            where button.identifier?.rawValue == key {
                button.state = button === sender ? .on : .off
            }
        }
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        views.forEach { row.addArrangedSubview($0) }
        return row
    }

    private func addRow(_ views: [NSView]) {
        stack.addArrangedSubview(row(views))
    }

    /// 顶部对齐的一行（多行输入框旁边放标签时用，避免标签被垂直居中）
    private func addTopRow(_ views: [NSView]) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .top
        views.forEach { row.addArrangedSubview($0) }
        stack.addArrangedSubview(row)
    }

    // MARK: 各类规则的界面

    private func build() {
        switch rule.kind {
        case .insert: buildInsert()
        case .delete: buildDelete()
        case .remove: buildRemove()
        case .replace: buildReplace()
        case .changeCase: buildCase()
        case .sequence: buildSequence()
        case .randomize: buildRandomize()
        case .dateFormat: buildDate()
        }
    }

    private func buildInsert() {
        addRow([label("插入："), textField("text", rule.text, width: 300)])
        addRow([label("位置："), radioRow("anchor", AnchorPosition.allCases.map(\.title), rule.anchor.index)])
        addRow([label("位置序号："), intField("offset", rule.offset, width: 56),
                hint("选「指定位置」时生效，表示插到第几个字符之后")])
        addRow([checkbox("ignExt", "忽略扩展名", rule.ignoreExtension)])
    }

    private func buildDelete() {
        addRow([label("始于："),
                radioRow("fromMode", ["位置：", "分隔符："], rule.deleteUseDelimiterFrom ? 1 : 0),
                intField("fromOffset", rule.deleteFromOffset, width: 56),
                textField("fromDelim", rule.deleteFromDelimiter, width: 110)])
        addRow([label("直到："),
                radioRow("untilMode", ["计数：", "分隔符：", "直到末尾"],
                         rule.deleteUntilEnd ? 2 : (rule.deleteUseDelimiterUntil ? 1 : 0)),
                intField("untilCount", rule.deleteUntilCount, width: 56),
                textField("untilDelim", rule.deleteUntilDelimiter, width: 110)])
        addRow([checkbox("delCurrent", "删除当前名称", rule.deleteCurrentName),
                checkbox("fromRight", "从右到左", rule.deleteFromRight)])
        addRow([checkbox("ignExt", "忽略扩展名", rule.ignoreExtension),
                checkbox("keepDelim", "禁止移除分隔符", rule.deleteKeepDelimiter)])
    }

    private func buildRemove() {
        addRow([label("移除："), textField("text", rule.text, width: 300)])
        addRow([label("操作序数："), radioRow("ordinal", RuleOrdinal.allCases.map(\.title), rule.ordinal.index)])
        addRow([checkbox("caseSensitive", "区分大小写", rule.caseSensitive),
                checkbox("wholeWord", "仅全字", rule.wholeWord)])
        addRow([checkbox("ignExt", "忽略扩展名", rule.ignoreExtension),
                checkbox("wildcard", "使用通配符 ? 和 *", rule.wildcard)])
    }

    private func buildReplace() {
        addRow([label("查找："), textField("text", rule.text, width: 300)])
        addRow([label("替换："), textField("replacement", rule.replacement, width: 300)])
        addRow([label("操作序数："), radioRow("ordinal", RuleOrdinal.allCases.map(\.title), rule.ordinal.index)])
        addRow([checkbox("caseSensitive", "区分大小写", rule.caseSensitive),
                checkbox("wholeWord", "仅全字", rule.wholeWord)])
        addRow([checkbox("ignExt", "忽略扩展名", rule.ignoreExtension),
                checkbox("wildcard", "使用通配符 ?、* 和 $n 反向引用", rule.wildcard)])
    }

    private func buildExtension() {
        addRow([label("新扩展名："), textField("text", rule.text, width: 200)])
        addRow([hint("留空表示移除扩展名；不需要输入点号，例如 jpg")])
    }

    private func buildClear() {
        addRow([checkbox("letters", "英语字母", rule.includeLetters), hint("a–z A–Z")])
        addRow([checkbox("digits", "数字", rule.includeDigits), hint("0–9")])
        addRow([checkbox("symbols", "符号", rule.includeSymbols), hint("!#$%&'*+,-./:;=?@\\^_`|~")])
        addRow([checkbox("brackets", "括号", rule.includeBrackets), hint("() {} [] <>")])
        addRow([label("用户定义："), textField("custom", rule.customChars, width: 260)])
        addRow([label("Unicode："), textField("unicode", rule.unicodeRange, width: 260)])
        addRow([hint("Unicode 范围写法：4E00-9FFF，多段用逗号分隔")])
        addRow([label("范围："), radioRow("scope", ClearScope.allCases.map(\.title), rule.clearScope.index),
                checkbox("invert", "移除选定项外的全部字符", rule.clearInvert)])
        addRow([checkbox("ignExt", "忽略扩展名", rule.ignoreExtension)])
    }

    private func buildCase() {
        addRow([label("大小写："), radioRow("caseMode", RuleCaseMode.allCases.map(\.title), rule.caseMode.index)])
        addRow([checkbox("force", "强制应用于以下片段", !rule.forceSegments.isEmpty),
                textField("segments", rule.forceSegments, width: 220)])
        addRow([hint("多个片段用逗号分隔，例如 CD、DVD、DJ，命中的片段会整体大写")])
        addRow([checkbox("extLower", "扩展名始终小写", rule.extAlwaysLower),
                checkbox("extUpper", "扩展名始终大写", rule.extAlwaysUpper)])
        addRow([checkbox("ignExt", "忽略扩展名", rule.ignoreExtension)])
    }

    private func buildSequence() {
        addRow([label("起始值："), intField("start", rule.startValue),
                label("重复数：", width: 60), intField("repeat", rule.repeatCount)])
        addRow([label("增量："), intField("step", rule.step),
                label("补零长度：", width: 70), intField("pad", rule.padLength)])
        addRow([label("序列符号："), popup("numeral", NumeralSystem.allCases.map(\.title), rule.numeral.index)])
        addRow([label("插入位置："), radioRow("anchor", AnchorPosition.allCases.map(\.title), rule.anchor.index)])
        addRow([label("位置序号："), intField("offset", rule.offset, width: 56),
                hint("选「指定位置」时生效")])
        addRow([checkbox("ignExt", "忽略扩展名", rule.ignoreExtension)])
    }

    private func buildRandomize() {
        addRow([label("长度："), intField("length", rule.randomLength)])
        addRow([label("字符集："), textField("set", rule.randomSet, width: 320)])
        addRow([hint("默认小写字母 + 数字；生成结果作为前缀插入")])
    }

    private func buildFill() {
        addRow([label("填充内容："), textField("text", rule.text, width: 220)])
        addRow([label("总长度："), intField("length", rule.fillLength)])
        addRow([label("位置："), radioRow("anchor", ["前缀", "后缀"], rule.anchor == .suffix ? 1 : 0)])
        addRow([checkbox("ignExt", "忽略扩展名", rule.ignoreExtension)])
    }

    private func buildSanitize() {
        addRow([checkbox("illegal", "移除非法字符（/ \\ : * ? \" < > |）", rule.removeIllegalChars)])
        addRow([checkbox("underscore", "空格替换为下划线", rule.spacesToUnderscore)])
        addRow([checkbox("collapse", "合并连续空格", rule.collapseSpaces)])
        addRow([checkbox("trim", "去除首尾空格", rule.trimEdges)])
        addRow([checkbox("ignExt", "忽略扩展名", rule.ignoreExtension)])
    }

    private func buildDate() {
        addRow([label("格式："), textField("text", rule.text.isEmpty ? "yyyy-MM-dd" : rule.text, width: 240)])
        addRow([hint("使用文件的修改时间，例如 yyyy-MM-dd HH.mm.ss")])
        addRow([label("位置："), radioRow("anchor", ["前缀", "后缀"], rule.anchor == .suffix ? 1 : 0)])
    }

    private func buildRegex() {
        addRow([label("表达式："), textField("text", rule.text, width: 300)])
        addRow([label("替换为："), textField("replacement", rule.replacement, width: 300)])
        addRow([checkbox("caseSensitive", "区分大小写", rule.caseSensitive),
                checkbox("ignExt", "忽略扩展名", rule.ignoreExtension)])
        addRow([hint("替换文本里可用 $1..$9 引用捕获组")])
    }

    private func buildUserInput() {
        addRow([label("输入内容："), textField("text", rule.text, width: 300)])
        addRow([label("位置："), radioRow("anchor", AnchorPosition.allCases.map(\.title), rule.anchor.index)])
        addRow([label("位置序号："), intField("offset", rule.offset, width: 56),
                hint("选「指定位置」时生效")])
        addRow([checkbox("ignExt", "忽略扩展名", rule.ignoreExtension)])
    }

    private func buildMapping() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: 470).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 170).isActive = true

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 470, height: 170))
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = rule.mappingText
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        textViews["mapping"] = textView

        addTopRow([label("映射："), scroll])
        addRow([hint("每行一条：旧名称=>新名称（匹配整个名称，支持 = 或 Tab 分隔）")])
    }

    // MARK: 读取控件

    private func text(_ key: String) -> String {
        (controls[key] as? NSTextField)?.stringValue ?? ""
    }

    private func intValue(_ key: String) -> Int {
        Int(text(key).trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private func isOn(_ key: String) -> Bool {
        (controls[key] as? NSButton)?.state == .on
    }

    private func radio(_ key: String) -> Int {
        radioValues[key] ?? 0
    }

    private func popupIndex(_ key: String) -> Int {
        (controls[key] as? NSPopUpButton)?.indexOfSelectedItem ?? 0
    }

    /// 把界面上的值写回规则
    func commit() -> RenameRule {
        var result = rule
        switch result.kind {
        case .insert:
            result.text = text("text")
            result.anchor = AnchorPosition.at(radio("anchor"))
            result.offset = max(1, intValue("offset"))
            result.ignoreExtension = isOn("ignExt")
        case .delete:
            result.deleteUseDelimiterFrom = radio("fromMode") == 1
            result.deleteFromOffset = max(1, intValue("fromOffset"))
            result.deleteFromDelimiter = text("fromDelim")
            let until = radio("untilMode")
            result.deleteUntilEnd = until == 2
            result.deleteUseDelimiterUntil = until == 1
            result.deleteUntilCount = max(0, intValue("untilCount"))
            result.deleteUntilDelimiter = text("untilDelim")
            result.deleteCurrentName = isOn("delCurrent")
            result.deleteFromRight = isOn("fromRight")
            result.deleteKeepDelimiter = isOn("keepDelim")
            result.ignoreExtension = isOn("ignExt")
        case .remove:
            result.text = text("text")
            result.ordinal = RuleOrdinal.at(radio("ordinal"))
            result.caseSensitive = isOn("caseSensitive")
            result.wholeWord = isOn("wholeWord")
            result.wildcard = isOn("wildcard")
            result.ignoreExtension = isOn("ignExt")
        case .replace:
            result.text = text("text")
            result.replacement = text("replacement")
            result.ordinal = RuleOrdinal.at(radio("ordinal"))
            result.caseSensitive = isOn("caseSensitive")
            result.wholeWord = isOn("wholeWord")
            result.wildcard = isOn("wildcard")
            result.ignoreExtension = isOn("ignExt")
        case .changeCase:
            result.caseMode = RuleCaseMode.at(radio("caseMode"))
            result.forceSegments = isOn("force") ? text("segments") : ""
            result.extAlwaysLower = isOn("extLower")
            result.extAlwaysUpper = isOn("extUpper")
            result.ignoreExtension = isOn("ignExt")
        case .sequence:
            result.startValue = intValue("start")
            result.repeatCount = max(1, intValue("repeat"))
            result.step = intValue("step")
            result.padLength = max(0, intValue("pad"))
            result.numeral = NumeralSystem.at(popupIndex("numeral"))
            result.anchor = AnchorPosition.at(radio("anchor"))
            result.offset = max(1, intValue("offset"))
            result.ignoreExtension = isOn("ignExt")
        case .randomize:
            result.randomLength = max(1, intValue("length"))
            result.randomSet = text("set")
        case .dateFormat:
            result.text = text("text")
            result.anchor = radio("anchor") == 1 ? .suffix : .prefix
        }
        return result
    }
}

// MARK: - 规则编辑窗口

final class RuleEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private var rule: RenameRule
    private let isEditing: Bool
    private let onCommit: (RenameRule) -> Void
    private let kindTable = NSTableView()
    private let configContainer = NSView()
    private var configView: RuleConfigView?
    private var currentKind: RenameRuleKind

    init(rule: RenameRule, isEditing: Bool, onCommit: @escaping (RenameRule) -> Void) {
        self.rule = rule
        self.isEditing = isEditing
        self.onCommit = onCommit
        self.currentKind = rule.kind
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 580),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = isEditing ? "编辑规则" : "添加规则"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let listScroll = NSScrollView(frame: NSRect(x: 16, y: 72, width: 190, height: 490))
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .bezelBorder
        listScroll.autoresizingMask = [.height]

        kindTable.headerView = nil
        kindTable.rowHeight = 24
        kindTable.allowsMultipleSelection = false
        kindTable.style = .plain
        kindTable.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind")))
        kindTable.dataSource = self
        kindTable.delegate = self
        kindTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        listScroll.documentView = kindTable
        content.addSubview(listScroll)

        let title = NSTextField(labelWithString: "配置：")
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.frame = NSRect(x: 218, y: 548, width: 120, height: 18)
        title.autoresizingMask = [.minYMargin]
        content.addSubview(title)

        configContainer.frame = NSRect(x: 218, y: 72, width: 566, height: 470)
        configContainer.autoresizingMask = [.width, .height]
        content.addSubview(configContainer)

        let commitButton = NSButton(title: isEditing ? "保存修改" : "添加规则", target: self, action: #selector(commitRule))
        commitButton.frame = NSRect(x: 218, y: 20, width: 380, height: 32)
        commitButton.bezelStyle = .rounded
        commitButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(commitButton)

        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeEditor))
        closeButton.frame = NSRect(x: 654, y: 20, width: 130, height: 32)
        closeButton.bezelStyle = .rounded
        closeButton.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(closeButton)

        if let index = RenameRuleKind.allCases.firstIndex(of: rule.kind) {
            kindTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            kindTable.scrollRowToVisible(index)
        }
        showConfig(for: rule.kind)
    }

    private func showConfig(for kind: RenameRuleKind) {
        configView?.removeFromSuperview()
        var base = rule
        if base.kind != kind {
            // 切换规则类型时保留通用输入，其他配置取该类型默认值
            var fresh = RenameRule(kind: kind)
            fresh.enabled = base.enabled
            fresh.ignoreExtension = base.ignoreExtension
            if kind == .replace || kind == .remove {
                fresh.text = base.text
                fresh.replacement = base.replacement
            } else {
                fresh.text = base.text
            }
            base = fresh
        }
        currentKind = kind
        let view = RuleConfigView(rule: base)
        view.frame = configContainer.bounds
        view.autoresizingMask = [.width, .height]
        configContainer.addSubview(view)
        configView = view
    }

    @objc private func commitRule() {
        guard let view = configView else { return }
        var result = view.commit()
        result.kind = currentKind
        result.enabled = rule.enabled
        // 空白说明时给个占位，便于识别
        onCommit(result)
        closeEditor()
    }

    @objc private func closeEditor() {
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }

    // MARK: 表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        RenameRuleKind.allCases.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let kind = RenameRuleKind.allCases[row]
        let container = NSView()
        let label = NSTextField(labelWithString: kind.title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 6, y: 4, width: 160, height: 16)
        label.autoresizingMask = [.width]
        container.addSubview(label)
        return container
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = kindTable.selectedRow
        guard row >= 0, row < RenameRuleKind.allCases.count else { return }
        showConfig(for: RenameRuleKind.allCases[row])
    }
}

// MARK: - 预览表：Delete 键只从列表移除（不碰磁盘）

/// 预览表拦截 Delete / 向前删除，回调给窗口从 files 数组移除选中项，
/// 绝不会触发文件管理器的「移到废纸篓 / 直接删除」。
final class RenamePreviewTable: NSTableView {
    var onDeleteKeys: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        // 51 = Delete(退格键位)，117 = Forward Delete(Fn+Delete)
        if event.keyCode == 51 || event.keyCode == 117 {
            onDeleteKeys?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - 窗口内容视图：接收从文件管理器拖入的文件

/// 作为批量重命名窗口的 contentView，覆盖整个窗口区域接收 .fileURL 拖拽，
/// 拖入的文件交给 onDropFiles 去重追加到列表。
final class RenameDropView: NSView {
    var onDropFiles: (([URL]) -> Void)?
    private var dragActive = false

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([.fileURL])
    }

    convenience init() {
        self.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        autoresizingMask = [.width, .height]
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if dragActive {
            NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(rect: bounds).fill()
            let inset: CGFloat = 4
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                                      xRadius: 8, yRadius: 8)
            border.lineWidth = 3
            border.setLineDash([8, 5], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            border.stroke()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragActive = true
        needsDisplay = true
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragActive = false
        needsDisplay = true
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        if !urls.isEmpty { onDropFiles?(urls) }
        dragActive = false
        needsDisplay = true
        return !urls.isEmpty
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dragActive = false
        needsDisplay = true
    }
}

// MARK: - 批量重命名主窗口

final class BulkRenameWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {

    struct PreviewRow {
        let url: URL
        let name: String
        let newName: String
        let error: String?
    }

    /// 会话内保留上次使用的规则，关闭窗口再打开不用重配
    private static var lastRules: [RenameRule] = []

    var onClose: (() -> Void)?

    private var files: [URL]
    private var rules: [RenameRule]
    private var rows: [PreviewRow] = []
    private var ruleEditor: RuleEditorWindowController?

    private let rulesTable = NSTableView()
    private let previewTable = RenamePreviewTable()
    private let countLabel = NSTextField(labelWithString: "")
    private var removeButton = NSButton()
    private var upButton = NSButton()
    private var downButton = NSButton()

    init(files: [URL]) {
        self.files = files
        self.rules = Self.lastRules
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "批量重命名"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 560)
        super.init(window: window)
        window.delegate = self
        // 内容视图换成可接收拖拽的视图：把拖入的文件去重追加到列表
        let dropView = RenameDropView()
        dropView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 960, height: 700)
        dropView.onDropFiles = { [weak self] urls in self?.merge(urls) }
        window.contentView = dropView
        previewTable.onDeleteKeys = { [weak self] in self?.deleteSelectedFilesFromList() }
        applyDebugSeeds()
        buildUI()
        refresh()
        openDebugEditorIfNeeded()
    }

    /// 自动化/排查用：XSPACE_BULK_APPLY_KIND + XSPACE_BULK_APPLY_TEXT 预置一条规则
    private func applyDebugSeeds() {
        let environment = ProcessInfo.processInfo.environment
        guard let kindName = environment["XSPACE_BULK_APPLY_KIND"],
              let kind = RenameRuleKind(rawValue: kindName) else { return }
        var rule = RenameRule(kind: kind)
        rule.text = environment["XSPACE_BULK_APPLY_TEXT"] ?? ""
        rule.replacement = environment["XSPACE_BULK_APPLY_REPLACEMENT"] ?? ""
        rules.append(rule)
    }

    /// 自动化/排查用：XSPACE_BULK_RULE_KIND 直接打开对应规则的配置面板
    private func openDebugEditorIfNeeded() {
        guard let kindName = ProcessInfo.processInfo.environment["XSPACE_BULK_RULE_KIND"],
              let kind = RenameRuleKind(rawValue: kindName) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let editor = RuleEditorWindowController(rule: RenameRule(kind: kind), isEditing: false) { _ in }
            self.ruleEditor = editor
            self.presentEditor(editor)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 界面

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let width = content.bounds.width
        let height = content.bounds.height

        // 顶部操作栏
        let bar = NSView(frame: NSRect(x: 0, y: height - 44, width: width, height: 44))
        bar.autoresizingMask = [.width, .minYMargin]
        content.addSubview(bar)

        let addFiles = makeBarButton("添加文件…", symbol: "doc.badge.plus", action: #selector(addFiles))
        addFiles.frame = NSRect(x: 16, y: 8, width: 108, height: 28)
        bar.addSubview(addFiles)

        let addFolder = makeBarButton("添加文件夹…", symbol: "folder.badge.plus", action: #selector(addFolder))
        addFolder.frame = NSRect(x: 130, y: 8, width: 124, height: 28)
        bar.addSubview(addFolder)

        let previewButton = makeBarButton("预览", symbol: "eye", action: #selector(previewNow))
        previewButton.frame = NSRect(x: width - 260, y: 8, width: 84, height: 28)
        previewButton.autoresizingMask = [.minXMargin]
        bar.addSubview(previewButton)

        let renameButton = makeBarButton("重命名", symbol: "checkmark.circle.fill", action: #selector(performRename))
        renameButton.frame = NSRect(x: width - 168, y: 8, width: 152, height: 28)
        renameButton.autoresizingMask = [.minXMargin]
        renameButton.keyEquivalent = "\r"
        bar.addSubview(renameButton)

        // 规则区标题与操作按钮
        let rulesHeader = NSView(frame: NSRect(x: 0, y: height - 78, width: width, height: 30))
        rulesHeader.autoresizingMask = [.width, .minYMargin]
        content.addSubview(rulesHeader)

        let rulesTitle = NSTextField(labelWithString: "规则（按从上到下的顺序逐条应用）")
        rulesTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        rulesTitle.frame = NSRect(x: 16, y: 6, width: 320, height: 18)
        rulesHeader.addSubview(rulesTitle)

        let addRule = makeSmallButton("添加规则", action: #selector(addRule))
        addRule.frame = NSRect(x: width - 300, y: 2, width: 86, height: 24)
        addRule.autoresizingMask = [.minXMargin]
        rulesHeader.addSubview(addRule)

        removeButton = makeSmallButton("移除", action: #selector(removeRule))
        removeButton.frame = NSRect(x: width - 206, y: 2, width: 60, height: 24)
        removeButton.autoresizingMask = [.minXMargin]
        rulesHeader.addSubview(removeButton)

        upButton = makeSmallButton("上移", action: #selector(moveRuleUp))
        upButton.frame = NSRect(x: width - 142, y: 2, width: 60, height: 24)
        upButton.autoresizingMask = [.minXMargin]
        rulesHeader.addSubview(upButton)

        downButton = makeSmallButton("下移", action: #selector(moveRuleDown))
        downButton.frame = NSRect(x: width - 78, y: 2, width: 60, height: 24)
        downButton.autoresizingMask = [.minXMargin]
        rulesHeader.addSubview(downButton)

        // 规则表
        let rulesScroll = NSScrollView(frame: NSRect(x: 16, y: height - 78 - 8 - 176, width: width - 32, height: 176))
        rulesScroll.hasVerticalScroller = true
        rulesScroll.borderType = .bezelBorder
        rulesScroll.autoresizingMask = [.width, .minYMargin]
        rulesTable.headerView = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 24))
        rulesTable.rowHeight = 22
        rulesTable.usesAlternatingRowBackgroundColors = true
        rulesTable.allowsMultipleSelection = false
        rulesTable.style = .plain
        rulesTable.addTableColumn(column("enabled", "启用", 46))
        rulesTable.addTableColumn(column("index", "#", 34))
        rulesTable.addTableColumn(column("kind", "规则", 90))
        rulesTable.addTableColumn(column("summary", "说明", 640))
        rulesTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        rulesTable.dataSource = self
        rulesTable.delegate = self
        rulesTable.target = self
        rulesTable.doubleAction = #selector(editSelectedRule)
        rulesScroll.documentView = rulesTable
        content.addSubview(rulesScroll)

        // 分隔线
        let divider = NSBox(frame: NSRect(x: 16, y: height - 264, width: width - 32, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width, .minYMargin]
        content.addSubview(divider)

        // 预览表
        let previewScroll = NSScrollView(frame: NSRect(x: 16, y: 56, width: width - 32, height: height - 264 - 8 - 56))
        previewScroll.hasVerticalScroller = true
        previewScroll.borderType = .bezelBorder
        previewScroll.autoresizingMask = [.width, .height]
        previewTable.headerView = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 24))
        previewTable.rowHeight = 22
        previewTable.usesAlternatingRowBackgroundColors = true
        previewTable.allowsMultipleSelection = true
        previewTable.style = .plain
        previewTable.addTableColumn(column("state", "状态", 54))
        previewTable.addTableColumn(column("name", "名称", 330))
        previewTable.addTableColumn(column("newName", "新名称", 330))
        previewTable.addTableColumn(column("error", "错误信息", 300))
        previewTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        previewTable.dataSource = self
        previewTable.delegate = self
        previewScroll.documentView = previewTable
        content.addSubview(previewScroll)

        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.frame = NSRect(x: 16, y: 22, width: width - 32, height: 18)
        countLabel.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(countLabel)

        updateButtons()
    }

    private func column(_ id: String, _ title: String, _ width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = 30
        return column
    }

    private func makeBarButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 12)
        if let image = Symbol.image(symbol) {
            button.image = image
            button.imagePosition = .imageLeading
        }
        return button
    }

    private func makeSmallButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 12)
        return button
    }

    // MARK: 数据刷新

    private func saveRules() {
        Self.lastRules = rules
    }

    private func refresh() {
        rebuildPreview()
        rulesTable.reloadData()
        previewTable.reloadData()
        updateButtons()
        let changed = rows.filter { $0.name != $0.newName && $0.error == nil }.count
        let errors = rows.filter { $0.error != nil }.count
        var text = "共 \(rows.count) 个文件"
        if changed > 0 { text += " · \(changed) 个将被重命名" }
        if errors > 0 { text += " · \(errors) 个有问题" }
        countLabel.stringValue = text
    }

    private func rebuildPreview() {
        let activeRules = rules
        var result: [PreviewRow] = []
        var seen: [String: Int] = [:]
        let fileManager = FileManager.default
        for (index, url) in files.enumerated() {
            let name = url.lastPathComponent
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let context = RenameContext(index: index, url: url, isDirectory: isDirectory.boolValue, modified: modified)

            var newName = name
            if !activeRules.isEmpty {
                newName = RenameEngine.newName(originalName: name, rules: activeRules, context: context)
            }

            var error: String?
            if newName.isEmpty {
                error = "名称不能为空"
            } else if newName.contains("/") || newName.contains(":") {
                error = "名称含有非法字符"
            } else if newName.hasPrefix(".") {
                error = "名称不能以点开头"
            }
            let key = newName.lowercased()
            if let other = seen[key], other != index {
                error = "与第 \(other + 1) 项重名"
            } else {
                seen[key] = index
            }
            if error == nil, newName != name {
                let target = url.deletingLastPathComponent().appendingPathComponent(newName)
                if fileManager.fileExists(atPath: target.path) {
                    error = "目标名称已存在"
                }
            }
            result.append(PreviewRow(url: url, name: name, newName: newName, error: error))
        }
        rows = result
    }

    private func updateButtons() {
        let row = rulesTable.selectedRow
        let hasSelection = row >= 0 && row < rules.count
        removeButton.isEnabled = hasSelection
        upButton.isEnabled = hasSelection && row > 0
        downButton.isEnabled = hasSelection && row < rules.count - 1
    }

    // MARK: 表格数据源

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === rulesTable ? rules.count : rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        if tableView === rulesTable {
            switch column.identifier.rawValue {
            case "enabled":
                let container = NSView()
                let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRuleEnabled(_:)))
                button.frame = NSRect(x: 10, y: 2, width: 18, height: 18)
                button.state = rules[row].enabled ? .on : .off
                button.tag = row
                container.addSubview(button)
                return container
            case "index":
                return cellLabel("\(row + 1)", secondary: true)
            case "kind":
                return cellLabel(rules[row].kind.title)
            default:
                return cellLabel(rules[row].summary, secondary: true)
            }
        }
        switch column.identifier.rawValue {
        case "state":
            return cellLabel(rows[row].error == nil ? "就绪" : "错误",
                             color: rows[row].error == nil ? .secondaryLabelColor : .systemRed)
        case "name":
            return cellLabel(rows[row].name)
        case "newName":
            return cellLabel(rows[row].newName, color: rows[row].error == nil ? .labelColor : .systemRed)
        default:
            return cellLabel(rows[row].error ?? "", color: .systemRed)
        }
    }

    private func cellLabel(_ text: String, secondary: Bool = false) -> NSView {
        cellLabel(text, color: secondary ? .secondaryLabelColor : .labelColor)
    }

    private func cellLabel(_ text: String, color: NSColor) -> NSView {
        let container = NSView()
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: 4, y: 3, width: 900, height: 16)
        label.autoresizingMask = [.width]
        container.addSubview(label)
        return container
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }

    // MARK: 规则操作

    @objc private func addRule() {
        let editor = RuleEditorWindowController(rule: RenameRule(kind: .insert), isEditing: false) { [weak self] rule in
            guard let self else { return }
            self.rules.append(rule)
            self.saveRules()
            self.refresh()
            self.rulesTable.selectRowIndexes(IndexSet(integer: self.rules.count - 1), byExtendingSelection: false)
        }
        ruleEditor = editor
        presentEditor(editor)
    }

    @objc private func editSelectedRule() {
        let row = rulesTable.selectedRow
        guard row >= 0, row < rules.count else { return }
        let editor = RuleEditorWindowController(rule: rules[row], isEditing: true) { [weak self] rule in
            guard let self, row < self.rules.count else { return }
            self.rules[row] = rule
            self.saveRules()
            self.refresh()
        }
        ruleEditor = editor
        presentEditor(editor)
    }

    private func presentEditor(_ editor: RuleEditorWindowController) {
        guard let window, let editorWindow = editor.window else { return }
        window.beginSheet(editorWindow, completionHandler: nil)
    }

    @objc private func removeRule() {
        let row = rulesTable.selectedRow
        guard row >= 0, row < rules.count else { return }
        rules.remove(at: row)
        saveRules()
        refresh()
        if !rules.isEmpty {
            rulesTable.selectRowIndexes(IndexSet(integer: min(row, rules.count - 1)), byExtendingSelection: false)
        }
    }

    @objc private func moveRuleUp() {
        let row = rulesTable.selectedRow
        guard row > 0, row < rules.count else { return }
        rules.swapAt(row, row - 1)
        saveRules()
        refresh()
        rulesTable.selectRowIndexes(IndexSet(integer: row - 1), byExtendingSelection: false)
    }

    @objc private func moveRuleDown() {
        let row = rulesTable.selectedRow
        guard row >= 0, row < rules.count - 1 else { return }
        rules.swapAt(row, row + 1)
        saveRules()
        refresh()
        rulesTable.selectRowIndexes(IndexSet(integer: row + 1), byExtendingSelection: false)
    }

    @objc private func toggleRuleEnabled(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < rules.count else { return }
        rules[sender.tag].enabled = sender.state == .on
        saveRules()
        refresh()
    }

    // MARK: 文件与执行

    @objc private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "选择要重命名的文件"
        panel.prompt = "添加"
        if let directory = files.first?.deletingLastPathComponent() {
            panel.directoryURL = directory
        }
        guard panel.runModal() == .OK else { return }
        merge(panel.urls)
    }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "选择文件夹，添加其中的项目"
        panel.prompt = "添加"
        guard panel.runModal() == .OK else { return }
        var urls: [URL] = []
        for folder in panel.urls {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            urls.append(contentsOf: contents)
        }
        merge(urls)
    }

    private func merge(_ urls: [URL]) {
        let existing = Set(files.map(\.standardizedFileURL.path))
        var added: [URL] = []
        for url in urls where !existing.contains(url.standardizedFileURL.path) {
            if !files.contains(where: { $0.standardizedFileURL.path == url.standardizedFileURL.path }) {
                added.append(url)
            }
        }
        guard !added.isEmpty else { return }
        files.append(contentsOf: added)
        refresh()
    }

    /// 外部（选中项 / 拖拽）追加文件，统一走去重与预览刷新
    func appendFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        merge(urls)
    }

    /// 预览表按 Delete：只把选中项从列表（files）里移除，绝不触碰磁盘文件
    private func deleteSelectedFilesFromList() {
        let indexes = previewTable.selectedRowIndexes
        guard !indexes.isEmpty else { return }
        // 按行号从大到小移除，避免索引前移错位
        for index in indexes.sorted(by: >) where index < files.count {
            files.remove(at: index)
        }
        refresh()
    }

    @objc private func previewNow() {
        refresh()
    }

    @objc private func performRename() {
        let targets = rows.filter { $0.error == nil && $0.name != $0.newName }
        guard !targets.isEmpty else {
            Dialog.alert(title: "没有需要重命名的项目",
                         message: rules.isEmpty ? "请先添加规则。" : "当前规则没有改变任何名称。",
                         window: window)
            return
        }
        let message = "将重命名 \(targets.count) 个项目，可用 ⌘Z 撤销，请确认预览结果无误。"
        guard Dialog.confirm(title: "批量重命名", message: message, confirmTitle: "重命名", window: window) else { return }

        var failures: [String] = []
        var renamed: [URL: URL] = [:]
        var pairs: [(source: URL, destination: URL)] = []
        for row in targets {
            let destination = row.url.deletingLastPathComponent().appendingPathComponent(row.newName)
            do {
                try FileManager.default.moveItem(at: row.url, to: destination)
                renamed[row.url] = destination
                pairs.append((row.url, destination))
            } catch {
                failures.append("\(row.name)：\(error.localizedDescription)")
            }
        }
        if !pairs.isEmpty {
            FileUndoStack.shared.record("批量重命名 \(pairs.count) 个项目") {
                for pair in pairs.reversed() {
                    _ = UndoIO.move(pair.destination, to: pair.source)
                }
            }
        }
        files = files.map { renamed[$0] ?? $0 }
        refresh()

        if failures.isEmpty {
            Dialog.alert(title: "完成", message: "已重命名 \(targets.count) 个项目。", window: window)
        } else {
            let detail = failures.prefix(10).joined(separator: "\n")
            Dialog.alert(title: "部分项目重命名失败",
                         message: "成功 \(targets.count - failures.count) 个，失败 \(failures.count) 个。\n\(detail)",
                         window: window)
        }
    }

    // MARK: 窗口

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
