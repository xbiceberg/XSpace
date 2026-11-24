import Foundation

// MARK: - 规则的枚举选项

/// 匹配的序数：全部 / 首个 / 末个
enum RuleOrdinal: String, CaseIterable {
    case all, first, last

    var title: String {
        switch self {
        case .all: return "全部"
        case .first: return "首个"
        case .last: return "末个"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func at(_ index: Int) -> RuleOrdinal {
        allCases.indices.contains(index) ? allCases[index] : .all
    }
}

/// 文本插入位置
enum AnchorPosition: String, CaseIterable {
    case prefix, suffix, position, replaceName

    var title: String {
        switch self {
        case .prefix: return "前缀"
        case .suffix: return "后缀"
        case .position: return "指定位置"
        case .replaceName: return "替换当前名称"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func at(_ index: Int) -> AnchorPosition {
        allCases.indices.contains(index) ? allCases[index] : .prefix
    }
}

/// 大小写转换方式
enum RuleCaseMode: String, CaseIterable {
    case wordCap, lower, upper, invert, firstLetter, sentence, keep

    var title: String {
        switch self {
        case .wordCap: return "每个单词大写"
        case .lower: return "全部小写"
        case .upper: return "全部大写"
        case .invert: return "反转大小写"
        case .firstLetter: return "首字母大写"
        case .sentence: return "句首大写"
        case .keep: return "保留大小写"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func at(_ index: Int) -> RuleCaseMode {
        allCases.indices.contains(index) ? allCases[index] : .wordCap
    }
}

/// 序列化时使用的数字系统
enum NumeralSystem: String, CaseIterable {
    case decimal, octal, hexadecimal, alphaLower, alphaUpper, romanUpper

    var title: String {
        switch self {
        case .decimal: return "十进制数字 (0..9)"
        case .octal: return "八进制数字 (0..7)"
        case .hexadecimal: return "十六进制数字 (0..F)"
        case .alphaLower: return "小写字母 (a..z)"
        case .alphaUpper: return "大写字母 (A..Z)"
        case .romanUpper: return "罗马数字 (I, II, III)"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func at(_ index: Int) -> NumeralSystem {
        allCases.indices.contains(index) ? allCases[index] : .decimal
    }
}

/// 清除字符时的作用范围
enum ClearScope: String, CaseIterable {
    case anywhere, prefix, suffix

    var title: String {
        switch self {
        case .anywhere: return "任意位置"
        case .prefix: return "开头"
        case .suffix: return "尾随"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func at(_ index: Int) -> ClearScope {
        allCases.indices.contains(index) ? allCases[index] : .anywhere
    }
}

/// 支持的规则类型（对应「添加规则」左侧列表）
enum RenameRuleKind: String, CaseIterable {
    case insert
    case delete
    case remove
    case replace
    case changeCase
    case sequence
    case randomize
    case dateFormat

    var title: String {
        switch self {
        case .insert: return "插入"
        case .delete: return "删除"
        case .remove: return "移除"
        case .replace: return "替换"
        case .changeCase: return "大小写"
        case .sequence: return "序列化"
        case .randomize: return "随机化"
        case .dateFormat: return "日期格式转换"
        }
    }
}

// MARK: - 规则模型

struct RenameRule {
    var kind: RenameRuleKind
    var enabled: Bool = true

    /// 通用文本：插入内容 / 移除模式 / 查找内容 / 替换内容 / 新扩展名 / 填充内容 / 日期格式等
    var text: String = ""
    /// 替换（Replace）时使用的替换文本
    var replacement: String = ""
    /// 忽略扩展名（大部分规则都支持）
    var ignoreExtension: Bool = true
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
    var wildcard: Bool = false
    var ordinal: RuleOrdinal = .all

    /// 插入位置
    var anchor: AnchorPosition = .prefix
    var offset: Int = 1

    /// 删除规则：起始
    var deleteUseDelimiterFrom: Bool = false
    var deleteFromOffset: Int = 1
    var deleteFromDelimiter: String = ""
    /// 删除规则：结束
    var deleteUntilEnd: Bool = false
    var deleteUseDelimiterUntil: Bool = false
    var deleteUntilCount: Int = 1
    var deleteUntilDelimiter: String = ""
    var deleteCurrentName: Bool = false
    var deleteFromRight: Bool = false
    var deleteKeepDelimiter: Bool = false

    /// 大小写
    var caseMode: RuleCaseMode = .wordCap
    var forceSegments: String = ""
    var extAlwaysLower: Bool = false
    var extAlwaysUpper: Bool = false

    /// 序列化
    var startValue: Int = 1
    var step: Int = 1
    var repeatCount: Int = 1
    var padLength: Int = 0
    var numeral: NumeralSystem = .decimal

    /// 随机化
    var randomLength: Int = 8
    var randomSet: String = "abcdefghijklmnopqrstuvwxyz0123456789"

    /// 填充
    var fillLength: Int = 10

    /// 清除：字符类别
    var includeLetters: Bool = false
    var includeDigits: Bool = false
    var includeSymbols: Bool = false
    var includeBrackets: Bool = false
    var customChars: String = ""
    var unicodeRange: String = ""
    var clearScope: ClearScope = .anywhere
    var clearInvert: Bool = false

    /// 清理（Sanitize）
    var removeIllegalChars: Bool = true
    var spacesToUnderscore: Bool = false
    var collapseSpaces: Bool = true
    var trimEdges: Bool = true

    /// 映射：每行「旧名称=>新名称」
    var mappingText: String = ""

    /// 规则列表「说明」列的文字
    var summary: String {
        let quote = { (value: String) -> String in
            value.isEmpty ? "\"\"" : "\"\(value)\""
        }
        let ext = ignoreExtension ? "（忽略扩展名）" : ""
        switch kind {
        case .insert:
            switch anchor {
            case .prefix: return "插入 \(quote(text)) 作为前缀\(ext)"
            case .suffix: return "插入 \(quote(text)) 作为后缀\(ext)"
            case .position: return "在位置 \(offset) 插入 \(quote(text))\(ext)"
            case .replaceName: return "用 \(quote(text)) 替换当前名称\(ext)"
            }
        case .delete:
            if deleteCurrentName { return "删除当前名称\(ext)" }
            let from = deleteUseDelimiterFrom ? "分隔符 \(quote(deleteFromDelimiter)) 之后" : "位置 \(deleteFromOffset)"
            let until: String
            if deleteUntilEnd {
                until = "直到末尾"
            } else if deleteUseDelimiterUntil {
                until = "直到分隔符 \(quote(deleteUntilDelimiter))"
            } else {
                until = "共 \(deleteUntilCount) 个字符"
            }
            return "从\(from)删除\(until)\(ext)"
        case .remove:
            return "移除 \(quote(text))（\(ordinal.title)）\(ext)"
        case .replace:
            return "将 \(quote(text)) 替换为 \(quote(replacement))（\(ordinal.title)）\(ext)"
        case .changeCase:
            return "大小写：\(caseMode.title)\(ext)"
        case .sequence:
            return "序列化起始 \(startValue) 增量 \(step) 重复 \(repeatCount) 位置 \(anchor.title)\(ext)"
        case .randomize:
            return "随机化 \(randomLength) 个字符"
        case .dateFormat:
            return "日期 \(text) 作为\(anchor.title)"
        }
    }
}

// MARK: - 重命名引擎

/// 单个文件的重命名上下文
struct RenameContext {
    let index: Int
    let url: URL
    let isDirectory: Bool
    let modified: Date?
}

enum RenameEngine {

    /// 按顺序应用所有规则，得到新名称
    static func newName(originalName: String, rules: [RenameRule], context: RenameContext) -> String {
        var name = originalName
        for rule in rules where rule.enabled {
            name = apply(rule, to: name, context: context)
        }
        return name
    }

    static func apply(_ rule: RenameRule, to name: String, context: RenameContext) -> String {
        let parts = split(name, ignoreExtension: rule.ignoreExtension && !context.isDirectory)
        let base = parts.base
        let ext = parts.ext

        switch rule.kind {
        case .insert:
            return anchored(rule.text, on: base, anchor: rule.anchor, offset: rule.offset) + ext

        case .delete:
            return deletePart(base, rule: rule) + ext

        case .remove:
            return substitute(base, find: rule.text, replacement: "", rule: rule, isRegex: false) + ext

        case .replace:
            return substitute(base, find: rule.text, replacement: rule.replacement, rule: rule, isRegex: false) + ext

        case .changeCase:
            return changeCase(base, ext: ext, rule: rule)

        case .sequence:
            let repeats = max(1, rule.repeatCount)
            let value = rule.startValue + (context.index / repeats) * rule.step
            let token = numeral(value, system: rule.numeral, pad: rule.padLength)
            return anchored(token, on: base, anchor: rule.anchor, offset: rule.offset) + ext

        case .randomize:
            return anchored(randomString(length: rule.randomLength, set: rule.randomSet),
                            on: base, anchor: .prefix, offset: 1) + ext

        case .dateFormat:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = rule.text.isEmpty ? "yyyy-MM-dd" : rule.text
            let date = context.modified ?? Date()
            return anchored(formatter.string(from: date), on: base, anchor: rule.anchor, offset: rule.offset) + ext

        }
    }

    // MARK: - 名称拆分

    /// 拆分主名与扩展名（ext 含点号）
    static func split(_ name: String, ignoreExtension: Bool) -> (base: String, ext: String) {
        guard ignoreExtension else { return (name, "") }
        let ns = name as NSString
        let ext = ns.pathExtension
        guard !ext.isEmpty else { return (name, "") }
        return (ns.deletingPathExtension, "." + ext)
    }

    static func changeExtension(_ name: String, newExtension: String) -> String {
        let ns = name as NSString
        let base = ns.deletingPathExtension
        guard !base.isEmpty else { return name }   // .gitignore 之类的点文件不动
        let ext = newExtension.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return ext.isEmpty ? base : base + "." + ext
    }

    // MARK: - 位置插入

    static func anchored(_ text: String, on base: String, anchor: AnchorPosition, offset: Int) -> String {
        switch anchor {
        case .prefix:
            return text + base
        case .suffix:
            return base + text
        case .position:
            let characters = Array(base)
            let index = max(0, min(characters.count, offset - 1))
            return String(characters[0..<index]) + text + String(characters[index...])
        case .replaceName:
            return text
        }
    }

    // MARK: - 删除片段

    private static func deletePart(_ base: String, rule: RenameRule) -> String {
        if rule.deleteCurrentName { return "" }
        let characters = Array(base)
        guard !characters.isEmpty else { return base }

        // 起始位置
        var start = 0
        if rule.deleteUseDelimiterFrom {
            guard !rule.deleteFromDelimiter.isEmpty,
                  let range = findRange(of: rule.deleteFromDelimiter, in: base, fromRight: rule.deleteFromRight) else {
                return base
            }
            let upper = base.distance(from: base.startIndex, to: range.upperBound)
            let lower = base.distance(from: base.startIndex, to: range.lowerBound)
            start = rule.deleteFromRight ? lower : upper
        } else {
            start = max(0, rule.deleteFromOffset - 1)
        }
        start = min(start, characters.count)

        // 结束位置
        var end = characters.count
        if rule.deleteUntilEnd {
            end = characters.count
        } else if rule.deleteUseDelimiterUntil {
            guard !rule.deleteUntilDelimiter.isEmpty else { return base }
            let tail = String(characters[start...])
            if let range = findRange(of: rule.deleteUntilDelimiter, in: tail, fromRight: false) {
                end = start + tail.distance(from: tail.startIndex, to: range.lowerBound)
            } else {
                end = characters.count
            }
        } else {
            end = min(characters.count, start + max(0, rule.deleteUntilCount))
        }
        guard end > start else { return base }

        var result = String(characters[0..<start]) + String(characters[end...])
        if rule.deleteKeepDelimiter {
            if rule.deleteUseDelimiterFrom { result = rule.deleteFromDelimiter + result }
            if rule.deleteUseDelimiterUntil, !rule.deleteUntilEnd { result += rule.deleteUntilDelimiter }
        }
        return result
    }

    private static func findRange(of needle: String, in text: String, fromRight: Bool) -> Range<String.Index>? {
        guard !needle.isEmpty else { return nil }
        if fromRight {
            return text.range(of: needle, options: [.backwards, .caseInsensitive])
        }
        return text.range(of: needle, options: [.caseInsensitive])
    }

    // MARK: - 匹配与替换

    private static func makeRegex(find: String, rule: RenameRule, isRegex: Bool) -> NSRegularExpression? {
        var pattern: String
        if isRegex {
            pattern = find
        } else if rule.wildcard {
            pattern = globToRegex(find)
        } else {
            pattern = NSRegularExpression.escapedPattern(for: find)
        }
        guard !pattern.isEmpty else { return nil }
        if rule.wholeWord {
            pattern = "\\b(?:" + pattern + ")\\b"
        }
        let options: NSRegularExpression.Options = rule.caseSensitive ? [] : [.caseInsensitive]
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    static func globToRegex(_ glob: String) -> String {
        var out = ""
        for character in glob {
            switch character {
            case "*": out += ".*"
            case "?": out += "."
            default: out += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        return out
    }

    static func substitute(_ text: String, find: String, replacement: String,
                           rule: RenameRule, isRegex: Bool) -> String {
        guard let regex = makeRegex(find: find, rule: rule, isRegex: isRegex) else { return text }
        let source = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }

        let chosen: [NSTextCheckingResult]
        switch rule.ordinal {
        case .all: chosen = matches
        case .first: chosen = [matches[0]]
        case .last: chosen = [matches[matches.count - 1]]
        }

        let expand = isRegex || rule.wildcard
        let mutable = NSMutableString(string: text)
        for match in chosen.reversed() {
            let piece = expand ? expandTemplate(replacement, match: match, source: source) : replacement
            mutable.replaceCharacters(in: match.range, with: piece)
        }
        return mutable as String
    }

    /// 支持 $1..$9 的替换模板
    private static func expandTemplate(_ template: String, match: NSTextCheckingResult, source: NSString) -> String {
        let characters = Array(template)
        var out = ""
        var index = 0
        while index < characters.count {
            if characters[index] == "$", index + 1 < characters.count,
               let group = Int(String(characters[index + 1])), group < match.numberOfRanges {
                let range = match.range(at: group)
                if range.location != NSNotFound {
                    out += source.substring(with: range)
                }
                index += 2
                continue
            }
            out.append(characters[index])
            index += 1
        }
        return out
    }

    // MARK: - 清除字符

    private static func clearCharacters(_ text: String, rule: RenameRule) -> String {
        var set = CharacterSet()
        if rule.includeLetters { set.formUnion(.letters) }
        if rule.includeDigits { set.formUnion(.decimalDigits) }
        if rule.includeSymbols {
            set.formUnion(CharacterSet(charactersIn: "!#$%&'*+,-./:;=?@\\^_`|~"))
        }
        if rule.includeBrackets {
            set.formUnion(CharacterSet(charactersIn: "(){}[]<>"))
        }
        if !rule.customChars.isEmpty {
            set.formUnion(CharacterSet(charactersIn: rule.customChars))
        }
        if !rule.unicodeRange.isEmpty {
            set.formUnion(unicodeSet(from: rule.unicodeRange))
        }
        guard !set.isEmpty else { return text }

        func isSelected(_ character: Character) -> Bool {
            for scalar in character.unicodeScalars where set.contains(scalar) {
                return true
            }
            return false
        }
        // 非反选：删除命中字符；反选：只保留命中字符
        func keep(_ character: Character) -> Bool {
            rule.clearInvert ? isSelected(character) : !isSelected(character)
        }

        switch rule.clearScope {
        case .anywhere:
            return String(text.filter(keep))
        case .prefix:
            var characters = Array(text)
            var removed = 0
            while removed < characters.count, !keep(characters[removed]) { removed += 1 }
            characters.removeFirst(removed)
            return String(characters)
        case .suffix:
            var characters = Array(text)
            var removed = 0
            while removed < characters.count, !keep(characters[characters.count - 1 - removed]) { removed += 1 }
            characters.removeLast(removed)
            return String(characters)
        }
    }

    private static func unicodeSet(from spec: String) -> CharacterSet {
        var set = CharacterSet()
        let parts = spec.split(separator: ",")
        for part in parts {
            let bounds = part.split(separator: "-")
            if bounds.count == 2,
               let low = UInt32(String(bounds[0]).trimmingCharacters(in: .whitespaces), radix: 16),
               let high = UInt32(String(bounds[1]).trimmingCharacters(in: .whitespaces), radix: 16),
               low <= high {
                for value in low...high {
                    if let scalar = Unicode.Scalar(value) { set.insert(scalar) }
                }
            } else if let value = UInt32(String(part).trimmingCharacters(in: .whitespaces), radix: 16),
                      let scalar = Unicode.Scalar(value) {
                set.insert(scalar)
            }
        }
        return set
    }

    // MARK: - 大小写

    private static func changeCase(_ base: String, ext: String, rule: RenameRule) -> String {
        var name: String
        switch rule.caseMode {
        case .wordCap:
            name = base.capitalized
        case .lower:
            name = base.lowercased()
        case .upper:
            name = base.uppercased()
        case .invert:
            var out = ""
            for character in base {
                let text = String(character)
                let upper = text.uppercased()
                out += (text == upper) ? text.lowercased() : upper
            }
            name = out
        case .firstLetter:
            if let first = base.first {
                name = first.uppercased() + String(base.dropFirst())
            } else {
                name = base
            }
        case .sentence:
            var out = ""
            var capitalizeNext = true
            for character in base {
                if capitalizeNext, character.isLetter {
                    out += String(character).uppercased()
                    capitalizeNext = false
                } else {
                    out.append(character)
                    if ".!?".contains(character) { capitalizeNext = true }
                }
            }
            name = out
        case .keep:
            name = base
        }

        // 强制把某些片段整体大写，例如 CD、DVD、DJ
        let segments = rule.forceSegments
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for segment in segments {
            name = replaceIgnoringCase(name, target: segment, replacement: segment.uppercased())
        }

        var newExtension = ext
        if rule.extAlwaysLower { newExtension = newExtension.lowercased() }
        if rule.extAlwaysUpper { newExtension = newExtension.uppercased() }
        return name + newExtension
    }

    private static func replaceIgnoringCase(_ text: String, target: String, replacement: String) -> String {
        guard !target.isEmpty else { return text }
        return text.replacingOccurrences(of: target, with: replacement, options: [.caseInsensitive])
    }

    // MARK: - 序列号

    static func numeral(_ value: Int, system: NumeralSystem, pad: Int) -> String {
        var text: String
        switch system {
        case .decimal:
            text = String(value)
        case .octal:
            text = String(max(0, value), radix: 8)
        case .hexadecimal:
            text = String(max(0, value), radix: 16, uppercase: true)
        case .alphaLower:
            text = alpha(value, upper: false)
        case .alphaUpper:
            text = alpha(value, upper: true)
        case .romanUpper:
            text = roman(value)
        }
        while pad > 0, text.count < pad {
            text = "0" + text
        }
        return text
    }

    private static func alpha(_ value: Int, upper: Bool) -> String {
        guard value > 0 else { return String(value) }
        let baseValue = upper ? UnicodeScalar("A").value : UnicodeScalar("a").value
        var remaining = value
        var out = ""
        while remaining > 0 {
            remaining -= 1
            let offset = remaining % 26
            if let scalar = Unicode.Scalar(baseValue + UInt32(offset)) {
                out = String(Character(scalar)) + out
            }
            remaining /= 26
        }
        return out
    }

    private static func roman(_ value: Int) -> String {
        guard value > 0, value < 4000 else { return String(value) }
        let table: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
        ]
        var remaining = value
        var out = ""
        for (amount, symbol) in table {
            while remaining >= amount {
                out += symbol
                remaining -= amount
            }
        }
        return out
    }

    // MARK: - 随机化

    private static func randomString(length: Int, set: String) -> String {
        let pool = Array(set.isEmpty ? "abcdefghijklmnopqrstuvwxyz0123456789" : set)
        guard !pool.isEmpty else { return "" }
        return String((0..<max(0, length)).map { _ in pool.randomElement()! })
    }

    // MARK: - 清理

    private static func sanitize(_ base: String, rule: RenameRule) -> String {
        var name = base
        if rule.removeIllegalChars {
            let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
            name = String(name.unicodeScalars.filter { !illegal.contains($0) })
        }
        if rule.spacesToUnderscore {
            name = name.replacingOccurrences(of: " ", with: "_")
        }
        if rule.collapseSpaces {
            while name.contains("  ") {
                name = name.replacingOccurrences(of: "  ", with: " ")
            }
        }
        if rule.trimEdges {
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name
    }

    // MARK: - 映射

    private static func mapping(_ base: String, rule: RenameRule) -> String {
        let lines = rule.mappingText.split(whereSeparator: \.isNewline)
        for line in lines {
            let raw = String(line)
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let pair: (String, String)?
            if raw.contains("=>") {
                let parts = raw.components(separatedBy: "=>")
                pair = parts.count >= 2 ? (parts[0], parts.dropFirst().joined(separator: "=>")) : nil
            } else if raw.contains("\t") {
                let parts = raw.components(separatedBy: "\t")
                pair = parts.count >= 2 ? (parts[0], parts.dropFirst().joined(separator: "\t")) : nil
            } else if raw.contains("=") {
                let parts = raw.components(separatedBy: "=")
                pair = parts.count >= 2 ? (parts[0], parts.dropFirst().joined(separator: "=")) : nil
            } else {
                pair = nil
            }
            guard let (old, new) = pair else { continue }
            let pattern = old.trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty else { continue }
            let matched = rule.caseSensitive
                ? base == pattern
                : base.compare(pattern, options: .caseInsensitive) == .orderedSame
            if matched {
                return new.trimmingCharacters(in: .whitespaces)
            }
        }
        return base
    }
}
