import Foundation
import AppKit
import Carbon

/// 系统里可选择的一个键盘输入法 / 键盘布局。
struct XSpaceInputSource: Identifiable, Hashable {
    let id: String
    let name: String
    let isCJKV: Bool
}

/// 全局输入法锁定。
///
/// 思路参考 oomol-lab/LockIME：监听 `kTISNotifySelectedKeyboardInputSourceChanged`，
/// 偏离目标时用 Text Input Services 切回；带抑制窗口、延迟复核和安全输入字段避让，
/// 避免与系统/其它输入法管理器互相拉扯。
/// 这里没有复制 LockIME（GPL-3.0）的源码，只按其公开设计用系统 API 独立实现。
final class InputSourceLock {
    static let shared = InputSourceLock()

    private static let suppressWindow: TimeInterval = 0.30
    private static let conflictWindow: TimeInterval = 5.0
    private static let conflictPause: TimeInterval = 10.0
    private static let maxConflictReverts = 4

    private var started = false
    private var settleUntil = Date.distantPast
    private var pausedUntil = Date.distantPast
    private var recentReverts: [Date] = []
    private var reconcileGeneration = 0
    private var secureWatchPending = false

    var isEnabled: Bool { AppSettings.inputSourceLockEnabled }
    var targetID: String? { AppSettings.inputSourceLockID }

    var targetName: String? {
        guard let targetID else { return nil }
        return source(with: targetID).flatMap { stringProperty($0, kTISPropertyLocalizedName) } ?? targetID
    }

    var statusSummary: String {
        guard isEnabled else { return "输入法锁定：关闭" }
        guard let targetID else { return "输入法锁定：未选择输入法" }
        return "输入法锁定：\(targetName ?? targetID)"
    }

    // MARK: - 生命周期

    func start() {
        guard !started else { return }
        started = true
        installObservers()
        if isEnabled { applySavedTarget() }
    }

    private func installObservers() {
        let center = CFNotificationCenterGetDistributedCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center, observer,
            { _, opaque, _, _, _ in
                guard let opaque else { return }
                let lock = Unmanaged<InputSourceLock>.fromOpaque(opaque).takeUnretainedValue()
                DispatchQueue.main.async { lock.handleSourceChange() }
            },
            kTISNotifySelectedKeyboardInputSourceChanged, nil, .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center, observer,
            { _, opaque, _, _, _ in
                guard opaque != nil else { return }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .xspaceInputSourceListChanged, object: nil)
                }
            },
            kTISNotifyEnabledKeyboardInputSourcesChanged, nil, .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    // MARK: - 公开操作

    func setEnabled(_ enabled: Bool) {
        AppSettings.inputSourceLockEnabled = enabled
        if enabled {
            applySavedTarget()
        } else {
            settleUntil = .distantPast
            pausedUntil = .distantPast
            recentReverts.removeAll()
            reconcileGeneration += 1
        }
        NotificationCenter.default.post(name: .xspaceInputSourceChanged, object: nil)
    }

    func choose(_ id: String?) {
        AppSettings.inputSourceLockID = id
        reconcileGeneration += 1
        settleUntil = .distantPast
        recentReverts.removeAll()
        if isEnabled { applySavedTarget() }
        NotificationCenter.default.post(name: .xspaceInputSourceChanged, object: nil)
    }

    func applySavedTarget() {
        guard isEnabled, let id = targetID, source(with: id) != nil else { return }
        enforce(reason: .engage)
    }

    func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return stringProperty(source, kTISPropertyInputSourceID)
    }

    func currentName() -> String {
        guard let id = currentID() else { return "未知" }
        return source(with: id).flatMap { stringProperty($0, kTISPropertyLocalizedName) } ?? id
    }

    func availableSources() -> [XSpaceInputSource] {
        guard let array = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
                as? [TISInputSource] else { return [] }
        let keyboardCategory = kTISCategoryKeyboardInputSource as String
        let result = array.compactMap { source -> XSpaceInputSource? in
            guard stringProperty(source, kTISPropertyInputSourceCategory) == keyboardCategory,
                  boolProperty(source, kTISPropertyInputSourceIsEnabled),
                  boolProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  let id = stringProperty(source, kTISPropertyInputSourceID),
                  let name = stringProperty(source, kTISPropertyLocalizedName)
            else { return nil }
            return XSpaceInputSource(id: id, name: name, isCJKV: isCJKV(source))
        }
        return result.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: - 锁定状态机

    private enum Reason {
        case engage
        case drift
    }

    private func handleSourceChange() {
        NotificationCenter.default.post(name: .xspaceInputSourceChanged, object: nil)
        guard isEnabled, let target = targetID else { return }
        if currentID() == target {
            reconcileGeneration += 1
            return
        }
        enforce(reason: .drift)
    }

    private func enforce(reason: Reason) {
        guard isEnabled, let target = targetID else { return }
        let now = Date()
        if now < pausedUntil {
            scheduleReconcileAfterPause()
            return
        }
        // 密码框等安全输入期间系统强制 ASCII，此时不抢；离开后由轮询补回。
        if IsSecureEventInputEnabled() {
            scheduleSecureInputWatch()
            return
        }
        if currentID() == target {
            reconcileGeneration += 1
            settleUntil = .distantPast
            return
        }
        // 避免自己的切换通知形成回声。
        if now < settleUntil {
            scheduleReconcile()
            return
        }
        if reason == .drift, registerConflictRevert(now) {
            pausedUntil = now.addingTimeInterval(Self.conflictPause)
            recentReverts.removeAll()
            scheduleReconcileAfterPause()
            return
        }
        force(target)
    }

    private func force(_ id: String) {
        let ok = selectSource(id)
        settleUntil = Date().addingTimeInterval(Self.suppressWindow)
        scheduleReconcile()
        NotificationCenter.default.post(name: .xspaceInputSourceChanged, object: nil)
        _ = ok
    }

    private func registerConflictRevert(_ now: Date) -> Bool {
        recentReverts.removeAll { now.timeIntervalSince($0) > Self.conflictWindow }
        guard recentReverts.count < Self.maxConflictReverts else { return true }
        recentReverts.append(now)
        return false
    }

    private func scheduleReconcile() {
        reconcileGeneration += 1
        let generation = reconcileGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.suppressWindow + 0.02) { [weak self] in
            guard let self, self.reconcileGeneration == generation else { return }
            self.enforce(reason: .drift)
        }
    }

    private func scheduleReconcileAfterPause() {
        let delay = max(0.05, pausedUntil.timeIntervalSinceNow + 0.02)
        reconcileGeneration += 1
        let generation = reconcileGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.reconcileGeneration == generation else { return }
            self.enforce(reason: .drift)
        }
    }

    private func scheduleSecureInputWatch() {
        guard !secureWatchPending else { return }
        secureWatchPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.secureWatchPending = false
            self.enforce(reason: .drift)
        }
    }

    // MARK: - TIS 封装

    private func source(with id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let array = TISCreateInputSourceList(filter, false)?.takeRetainedValue()
                as? [TISInputSource] else { return nil }
        return array.first
    }

    private func selectSource(_ id: String) -> Bool {
        guard let source = source(with: id),
              boolProperty(source, kTISPropertyInputSourceIsEnabled),
              boolProperty(source, kTISPropertyInputSourceIsSelectCapable)
        else { return false }
        // 中文/日文等输入法从后台直接 TISSelectInputSource 可能半切换；
        // 先尝试让键盘焦点所在进程自己切换，失败再退回公开 API。
        if isCJKV(source), FocusedProcessInputSelector.select(source) { return true }
        return TISSelectInputSource(source) == noErr
    }

    private func isCJKV(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
              let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]
        else { return false }
        return languages.contains { language in
            ["zh", "ja", "ko", "vi"].contains(String(language.prefix(2)).lowercased())
        }
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}

/// 通过 HIToolbox 的私有 TSM 端口，让当前键盘焦点进程自行切换输入法。
/// 所有私有符号运行时解析，任一环节失败就返回 false，由调用方退回公开 API。
private enum FocusedProcessInputSelector {
    private static let selectedMessageID: Int32 = 7
    private static let portName = "com.apple.tsm.portname"
    private static let replyMode = "com.workbuddy.xspace.ime-reply"
    private static let requestKey = "tsmInputSourceSelectedInpSrcKey"
    private static let replyErrorKey = "tsmInputModeReplyToServerErrorKey"

    static func select(_ source: TISInputSource) -> Bool {
        guard let api = API.shared,
              let pid = api.keyFocusPID(),
              pid != ProcessInfo.processInfo.processIdentifier,
              let flattened = api.flatten(source),
              let request = encode(flattened)
        else { return false }
        guard let reply = api.send(request, to: pid),
              let plist = try? PropertyListSerialization.propertyList(from: reply, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let status = dictionary[replyErrorKey] as? NSNumber
        else { return false }
        return status.int32Value == noErr
    }

    private static func encode(_ flattened: Any) -> Data? {
        let plist: [String: Any] = [requestKey: flattened]
        return try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    private struct API {
        typealias GetKeyFocusProcess = @convention(c) (
            UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>
        ) -> Int32
        typealias GetProcessPID = @convention(c) (
            UnsafePointer<ProcessSerialNumber>, UnsafeMutablePointer<pid_t>
        ) -> OSStatus
        typealias CreatePerProcessRemote = @convention(c) (
            CFAllocator?, CFString, pid_t
        ) -> Unmanaged<CFMessagePort>?
        typealias CreateFlattenedInputSource = @convention(c) (
            TISInputSource, UnsafeMutablePointer<Unmanaged<CFTypeRef>?>
        ) -> UInt8

        private let getKeyFocusProcess: GetKeyFocusProcess
        private let getProcessPID: GetProcessPID
        private let createPerProcessRemote: CreatePerProcessRemote
        private let createFlattenedInputSource: CreateFlattenedInputSource

        static let shared = API()

        private init?() {
            let handle = UnsafeMutableRawPointer(bitPattern: -2)
            guard let focus = dlsym(handle, "CPSGetKeyFocusProcess"),
                  let pid = dlsym(handle, "GetProcessPID"),
                  let port = dlsym(handle, "CFMessagePortCreatePerProcessRemote"),
                  let flatten = dlsym(handle, "_CreateFlattenedInputSource")
            else { return nil }
            getKeyFocusProcess = unsafeBitCast(focus, to: GetKeyFocusProcess.self)
            getProcessPID = unsafeBitCast(pid, to: GetProcessPID.self)
            createPerProcessRemote = unsafeBitCast(port, to: CreatePerProcessRemote.self)
            createFlattenedInputSource = unsafeBitCast(flatten, to: CreateFlattenedInputSource.self)
        }

        func keyFocusPID() -> pid_t? {
            var process = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kNoProcess))
            var ignored: UInt8 = 0
            var pid: pid_t = 0
            guard getKeyFocusProcess(&process, &ignored) == 0,
                  getProcessPID(&process, &pid) == noErr,
                  pid > 0
            else { return nil }
            return pid
        }

        func flatten(_ source: TISInputSource) -> Any? {
            var flattened: Unmanaged<CFTypeRef>?
            guard createFlattenedInputSource(source, &flattened) != 0 else { return nil }
            return flattened?.takeRetainedValue()
        }

        func send(_ request: Data, to pid: pid_t) -> Data? {
            guard let remote = createPerProcessRemote(nil, portName as CFString, pid)?.takeRetainedValue()
            else { return nil }
            var reply: Unmanaged<CFData>?
            let status = CFMessagePortSendRequest(
                remote,
                selectedMessageID,
                request as CFData,
                0.1,
                0.3,
                replyMode as CFString,
                &reply
            )
            guard status == kCFMessagePortSuccess else { return nil }
            return reply?.takeRetainedValue() as Data?
        }
    }
}
