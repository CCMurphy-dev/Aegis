import CoreGraphics
import Foundation

/// The keyboard behaviour to use while the app switcher is visible.
///
/// Filter mode preserves Aegis's original type-to-filter interaction. Action
/// mode reserves W and Q for window management and keeps `:` for commands.
enum AppSwitcherKeyboardMode: String, CaseIterable, Codable {
    case filter
    case actions

    var displayName: String {
        switch self {
        case .filter: "Filter"
        case .actions: "Actions"
        }
    }
}

enum AppSwitcherWindowAction: Equatable {
    case close
    case quit
}

/// Exact command arguments for window-manager close operations.
/// Keeping them here makes the adapters thin and lets unit tests lock the
/// target-window syntax without launching a window manager.
enum WindowManagerCloseCommand: Equatable {
    case rift(Int)
    case aeroSpace(Int)
    case yabai(Int)

    var arguments: [String] {
        switch self {
        case .rift(let id):
            ["execute", "window", "close", "--window-id", "\(id)"]
        case .aeroSpace(let id):
            ["close", "--window-id", "\(id)"]
        case .yabai(let id):
            ["-m", "window", "\(id)", "--close"]
        }
    }
}

/// PID reuse is possible on macOS. Only use a PID lookup when it still names
/// the selected bundle; otherwise resolve the row's exact bundle identity.
enum AppSwitcherQuitTargetPolicy {
    static func pidMatches(
        expectedBundleIdentifier: String?,
        actualBundleIdentifier: String?
    ) -> Bool {
        guard let expectedBundleIdentifier else { return false }
        return expectedBundleIdentifier == actualBundleIdentifier
    }

    static func mayUseBundleFallback(processIdentifier: pid_t) -> Bool {
        processIdentifier <= 0
    }
}

/// Retains consumed action keys until their matching key-up arrives, even if
/// the switcher dismisses in between. That prevents an unmatched key-up from
/// reaching the newly focused application.
struct AppSwitcherConsumedKeyUpPolicy {
    private var consumedKeyCodes: Set<Int64> = []

    mutating func consume(_ keyCode: Int64) {
        consumedKeyCodes.insert(keyCode)
    }

    mutating func shouldSuppressKeyUp(_ keyCode: Int64) -> Bool {
        consumedKeyCodes.remove(keyCode) != nil
    }

    func shouldSuppressRepeatedKeyDown(_ keyCode: Int64, isAutorepeat: Bool) -> Bool {
        isAutorepeat && consumedKeyCodes.contains(keyCode)
    }

    mutating func reset() {
        consumedKeyCodes.removeAll()
    }
}

enum AppSwitcherActionKeyDecision: Equatable {
    case perform(AppSwitcherWindowAction)
    case enterCommandPalette
    case consume
    case passThrough
}

struct AppSwitcherDeferredConfirmation {
    private var isPending = false

    /// Returns true when Command release may confirm immediately. If a window
    /// action is still settling, remember the release for that action's
    /// confirmed completion instead.
    mutating func commandReleased(actionInFlight: Bool) -> Bool {
        guard actionInFlight else { return true }
        isPending = true
        return false
    }

    mutating func actionSettled() -> Bool {
        defer { isPending = false }
        return isPending
    }

    mutating func reset() {
        isPending = false
    }
}

enum AppSwitcherActivationPolicy {
    static func shouldBeginActivation(
        isSwitcherActive: Bool,
        isActivationPending: Bool
    ) -> Bool {
        !isSwitcherActive && !isActivationPending
    }

    static func shouldHandleActionKeys(
        isSwitcherActive: Bool,
        isActivationPending: Bool
    ) -> Bool {
        isSwitcherActive || isActivationPending
    }
}

struct AppSwitcherPendingCyclePolicy {
    private var queuedDirections: [Bool] = []

    mutating func enqueue(reverse: Bool) {
        queuedDirections.append(reverse)
    }

    mutating func applying(to index: Int, windowCount: Int) -> Int {
        defer { queuedDirections.removeAll() }
        guard windowCount > 0 else { return index }
        return queuedDirections.reduce(index) { current, reverse in
            reverse
                ? (current - 1 + windowCount) % windowCount
                : (current + 1) % windowCount
        }
    }

    mutating func reset() {
        queuedDirections.removeAll()
    }
}

/// Pure input policy for the switcher's action keyboard mode.
///
/// The interface is deliberately small: the event tap asks for one decision,
/// while all AppKit, WM, and refresh work stays in AppSwitcherService.
struct AppSwitcherActionKeyPolicy {
    static let qKeyCode: Int64 = 12
    static let wKeyCode: Int64 = 13
    static let semicolonKeyCode: Int64 = 41

    static func isPrintableKey(_ keyCode: Int64) -> Bool {
        switch keyCode {
        case 0...35, 37...47, 49, 50, 65, 67, 69, 75, 78, 81...92:
            true
        default:
            false
        }
    }

    static func isPrintableKey(_ keyCode: Int64, characters: String?) -> Bool {
        if let characters, !characters.isEmpty {
            return characters.unicodeScalars.contains {
                !CharacterSet.controlCharacters.contains($0)
            }
        }
        return isPrintableKey(keyCode)
    }

    static func decision(
        for keyCode: Int64,
        characters: String? = nil,
        flags: CGEventFlags,
        mode: AppSwitcherKeyboardMode,
        isCommandMode: Bool,
        isAutorepeat: Bool,
        isActivationPending: Bool = false
    ) -> AppSwitcherActionKeyDecision {
        guard mode == .actions, !isCommandMode else { return .passThrough }

        // Cmd+Tab has already been consumed, but the asynchronous window
        // query has not populated a selected row yet. Consume printable keys
        // here so its action chords cannot reach the foreground app.
        if isActivationPending {
            return isPrintableKey(keyCode, characters: characters) ? .consume : .passThrough
        }

        // `:` is the one normal text entry in action mode. It always opens
        // the palette before W/Q are considered, including Cmd+Shift+;.
        if characters == ":" ||
            (characters == nil && keyCode == semicolonKeyCode && flags.contains(.maskShift)) {
            return .enterCommandPalette
        }

        let actionModifiers = flags.contains(.maskCommand) &&
            !flags.contains(.maskAlternate) &&
            !flags.contains(.maskControl) &&
            !flags.contains(.maskShift)

        if actionModifiers {
            switch characters?.lowercased() {
            case "w": return isAutorepeat ? .consume : .perform(.close)
            case "q": return isAutorepeat ? .consume : .perform(.quit)
            case .none:
                // Tests and synthetic callers may not have a CGEvent. Live
                // keyboard handling always supplies the layout-aware text.
                if keyCode == wKeyCode {
                    return isAutorepeat ? .consume : .perform(.close)
                }
                if keyCode == qKeyCode {
                    return isAutorepeat ? .consume : .perform(.quit)
                }
            default:
                break
            }
        }

        // Do not leak Cmd-printable shortcuts into the selected application
        // while action mode is open. Non-printable navigation still uses the
        // service's normal arrow, number, and escape handling.
        return isPrintableKey(keyCode, characters: characters) ? .consume : .passThrough
    }
}

struct AppSwitcherWindowTarget: Equatable {
    let windowManagerID: Int
    let processIdentifier: pid_t
    let bundleIdentifier: String?
}

enum AppSwitcherActionTarget: Equatable {
    case windowTarget(AppSwitcherWindowTarget)
    case application(processIdentifier: pid_t, bundleIdentifier: String)

    static func window(
        windowManagerID: Int,
        processIdentifier: pid_t = 0,
        bundleIdentifier: String? = nil
    ) -> Self {
        .windowTarget(AppSwitcherWindowTarget(
            windowManagerID: windowManagerID,
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier
        ))
    }

    func matches(_ window: SwitcherWindow, confirmedRemoval: Bool = false) -> Bool {
        switch self {
        case .windowTarget(let target):
            guard window.windowManagerID == target.windowManagerID else { return false }
            if target.processIdentifier > 0,
               window.pid != target.processIdentifier {
                return false
            }
            if let bundleIdentifier = target.bundleIdentifier,
               window.bundleIdentifier != bundleIdentifier,
               !(confirmedRemoval && window.bundleIdentifier == nil) {
                return false
            }
            return true
        case .application(let processIdentifier, let bundleIdentifier):
            return window.pid == processIdentifier &&
                (window.bundleIdentifier == bundleIdentifier ||
                    (confirmedRemoval && window.bundleIdentifier == nil))
        }
    }
}

enum AppSwitcherActionTargetPolicy {
    static func isGone(
        _ target: AppSwitcherActionTarget,
        from windows: [SwitcherWindow]
    ) -> Bool {
        !windows.contains { target.matches($0) }
    }
}

enum AppSwitcherActionContentPolicy {
    static func reconciledContent(
        refreshed: SwitcherContent,
        previous: SwitcherContent,
        target: AppSwitcherActionTarget,
        check: WMAppSwitcherTargetCheck,
        absentWindowManagerIDs: Set<Int> = []
    ) -> SwitcherContent {
        let refreshed = removingWindows(
            absentWindowManagerIDs,
            from: refreshed,
            matching: target
        )
        if check == .absent {
            return removeConfirmedTarget(from: refreshed, target: target, check: check)
        }

        let isTarget: (SwitcherWindow) -> Bool = { target.matches($0) }
        let identity: (SwitcherWindow) -> Int = { $0.windowManagerID ?? $0.id }
        let previousTargets = previous.allWindows.filter(isTarget)
        let retainedTargetIDs: Set<Int>
        switch target {
        case .windowTarget:
            retainedTargetIDs = Set(previousTargets.map(identity))
                .subtracting(absentWindowManagerIDs)
        case .application:
            // A live application can close some clean windows while leaving
            // one save prompt. When the refreshed snapshot already contains
            // that process, it is authoritative for which rows survived.
            // If the manager temporarily omitted the whole process, retain a
            // single representative row rather than resurrecting every old
            // document window.
            retainedTargetIDs = refreshed.allWindows.contains(where: isTarget)
                ? []
                : Set(previousTargets.lazy
                    .filter { !absentWindowManagerIDs.contains(identity($0)) }
                    .prefix(1)
                    .map(identity))
        }
        let shouldRetain: (SwitcherWindow) -> Bool = {
            isTarget($0) && retainedTargetIDs.contains(identity($0))
        }

        var allWindows = refreshed.allWindows
        for (previousIndex, window) in previous.allWindows.enumerated()
        where shouldRetain(window) && !allWindows.contains(where: { identity($0) == identity(window) }) {
            allWindows.insert(window, at: min(previousIndex, allWindows.count))
        }

        var groups = refreshed.spaceGroups
        for previousGroup in previous.spaceGroups {
            let retained = previousGroup.windows.filter(shouldRetain)
            guard !retained.isEmpty else { continue }
            if let groupIndex = groups.firstIndex(where: {
                $0.spaceIndex == previousGroup.spaceIndex
            }) {
                var windows = groups[groupIndex].windows
                for window in retained
                where !windows.contains(where: { identity($0) == identity(window) }) {
                    let previousIndex = previousGroup.windows.firstIndex(where: {
                        identity($0) == identity(window)
                    }) ?? windows.count
                    windows.insert(window, at: min(previousIndex, windows.count))
                }
                groups[groupIndex] = SpaceGroup(
                    spaceIndex: groups[groupIndex].spaceIndex,
                    spaceLabel: groups[groupIndex].spaceLabel,
                    isFocused: groups[groupIndex].isFocused,
                    windows: windows
                )
            } else {
                groups.append(SpaceGroup(
                    spaceIndex: previousGroup.spaceIndex,
                    spaceLabel: previousGroup.spaceLabel,
                    isFocused: previousGroup.isFocused,
                    windows: retained
                ))
            }
        }

        return SwitcherContent(spaceGroups: groups, allWindows: allWindows)
    }

    private static func removingWindows(
        _ windowManagerIDs: Set<Int>,
        from content: SwitcherContent,
        matching target: AppSwitcherActionTarget
    ) -> SwitcherContent {
        guard !windowManagerIDs.isEmpty else { return content }
        let keep: (SwitcherWindow) -> Bool = {
            guard let id = $0.windowManagerID else { return true }
            return !windowManagerIDs.contains(id) ||
                !target.matches($0, confirmedRemoval: true)
        }
        return SwitcherContent(
            spaceGroups: content.spaceGroups.compactMap { group in
                let windows = group.windows.filter(keep)
                return windows.isEmpty ? nil : SpaceGroup(
                    spaceIndex: group.spaceIndex,
                    spaceLabel: group.spaceLabel,
                    isFocused: group.isFocused,
                    windows: windows
                )
            },
            allWindows: content.allWindows.filter(keep)
        )
    }

    static func refreshResult(
        for confirmedCheck: WMAppSwitcherTargetCheck
    ) -> AppSwitcherActionRefreshResult {
        confirmedCheck == .absent ? .targetGone : .targetStillPresent
    }

    static func confirmedCheck(
        _ managerCheck: WMAppSwitcherTargetCheck,
        target: AppSwitcherActionTarget,
        runningBundleIdentifier: String?
    ) -> WMAppSwitcherTargetCheck {
        guard case .application(_, let expectedBundleIdentifier) = target else {
            return managerCheck
        }

        // A graceful quit may replace the original document window with a
        // save prompt. The exact process still running is authoritative proof
        // that Q has not completed, even if the original WM IDs disappeared.
        // Conversely, the exact PID disappearing (or being reused by another
        // bundle) proves this application target is gone even if the WM is
        // unavailable and its cached fallback row remains.
        return runningBundleIdentifier == expectedBundleIdentifier ? .present : .absent
    }

    static func checkPresence(
        _ target: AppSwitcherActionTarget,
        in windows: [SwitcherWindow]
    ) -> WMAppSwitcherTargetCheck {
        switch target {
        case .windowTarget:
            return windows.contains { target.matches($0) } ? .present : .absent
        case .application(let processIdentifier, let bundleIdentifier):
            return windows.contains {
                $0.pid == processIdentifier && $0.bundleIdentifier == bundleIdentifier
            } ? .present : .absent
        }
    }

    /// Filter rows only after a manager has confirmed that the action target
    /// disappeared. A present row can represent a save prompt, and an
    /// unavailable check must never be interpreted as a close.
    static func removeConfirmedTarget(
        from content: SwitcherContent,
        target: AppSwitcherActionTarget,
        check: WMAppSwitcherTargetCheck
    ) -> SwitcherContent {
        guard check == .absent else { return content }

        let keep: (SwitcherWindow) -> Bool = {
            !target.matches($0, confirmedRemoval: true)
        }

        return SwitcherContent(
            spaceGroups: content.spaceGroups.compactMap { group in
                let windows = group.windows.filter(keep)
                return windows.isEmpty ? nil : SpaceGroup(
                    spaceIndex: group.spaceIndex,
                    spaceLabel: group.spaceLabel,
                    isFocused: group.isFocused,
                    windows: windows
                )
            },
            allWindows: content.allWindows.filter(keep)
        )
    }
}

enum YabaiWindowBundleResolver {
    static func resolve(
        processIdentifier: pid_t,
        lookup: (pid_t) -> String?
    ) -> String? {
        guard processIdentifier > 0 else { return nil }
        return lookup(processIdentifier)
    }
}

enum AppSwitcherActionRefreshResult: Equatable {
    case targetGone
    case targetStillPresent
    case unavailable
}

/// Owns one app-switcher mutation and its event-first, bounded fallback
/// refresh cycle. Window-manager events are the preferred signal because they
/// arrive after the manager's cache has changed. Timers only cover managers
/// that do not emit an event (or emit it before their cache is ready).
final class AppSwitcherActionRefreshCoordinator {
    static let refreshDelays: [TimeInterval] = [0, 0.15, 0.45, 0.9, 1.5, 2.5]
    static let eventDebounceDelay: TimeInterval = 0.02
    // Let the final 2.5-second poll begin before the independent deadline
    // releases mutation ownership, even when both timers share one queue.
    static let actionDeadline: TimeInterval = 2.51

    static func fallbackDelay(at index: Int) -> TimeInterval {
        guard refreshDelays.indices.contains(index), index > 0 else { return 0 }
        let interval = refreshDelays[index] - refreshDelays[index - 1]
        return (interval * 1_000).rounded() / 1_000
    }

    typealias Schedule = (_ delay: TimeInterval, _ action: @escaping () -> Void) -> DispatchWorkItem
    typealias Now = () -> TimeInterval
    typealias Refresh = (@escaping (AppSwitcherActionRefreshResult) -> Void) -> Void

    private var generation = 0
    private var isMutating = false
    private var target: AppSwitcherActionTarget?
    private var refresh: Refresh?
    private var onConfirmed: (() -> Void)?
    private var onTimedOut: (() -> Void)?
    private var pendingWork: DispatchWorkItem?
    private var deadlineWork: DispatchWorkItem?
    private var refreshInFlight = false
    private var pendingEventRefresh = false
    private var nextFallbackIndex = 1
    private var actionStartedAt: TimeInterval = 0
    private var waitingForEvent = false
    private enum PendingWorkKind: Equatable {
        case fallback
        case event
    }
    private var pendingWorkKind: PendingWorkKind?
    private let schedule: Schedule
    private let deadlineSchedule: Schedule
    private let now: Now

    var hasActiveMutation: Bool { isMutating }
    var isWaitingForEvent: Bool { waitingForEvent }

    init(
        now: @escaping Now = { Date.timeIntervalSinceReferenceDate },
        deadlineSchedule: @escaping Schedule = AppSwitcherActionRefreshCoordinator.defaultSchedule,
        schedule: @escaping Schedule = AppSwitcherActionRefreshCoordinator.defaultSchedule
    ) {
        self.now = now
        self.deadlineSchedule = deadlineSchedule
        self.schedule = schedule
    }

    private static func defaultSchedule(
        delay: TimeInterval,
        action: @escaping () -> Void
    ) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return work
    }

    /// Compatibility entry point for callers/tests that only need ownership.
    func begin() -> Int? {
        begin(target: nil)
    }

    func begin(target: AppSwitcherActionTarget?) -> Int? {
        guard !isMutating else { return nil }
        if waitingForEvent {
            discardPassiveWait()
        }
        generation += 1
        isMutating = true
        waitingForEvent = false
        self.target = target
        nextFallbackIndex = 1
        actionStartedAt = now()
        pendingEventRefresh = false
        return generation
    }

    func cancel() {
        generation += 1
        pendingWork?.cancel()
        deadlineWork?.cancel()
        pendingWork = nil
        deadlineWork = nil
        pendingWorkKind = nil
        isMutating = false
        waitingForEvent = false
        target = nil
        refresh = nil
        onConfirmed = nil
        onTimedOut = nil
        refreshInFlight = false
        pendingEventRefresh = false
    }

    func isCurrent(_ token: Int) -> Bool {
        token == generation && (isMutating || waitingForEvent)
    }

    /// Starts the initial query. The callback should commit a valid snapshot
    /// before returning `.targetGone` or `.targetStillPresent`.
    func startWaiting(
        for token: Int,
        refresh: @escaping Refresh,
        onConfirmed: @escaping () -> Void,
        onTimedOut: @escaping () -> Void = {}
    ) {
        guard isCurrent(token) else { return }
        self.refresh = refresh
        self.onConfirmed = onConfirmed
        self.onTimedOut = onTimedOut
        let remaining = max(0, Self.actionDeadline - elapsedTime)
        deadlineWork?.cancel()
        deadlineWork = deadlineSchedule(remaining) { [weak self] in
            guard let self, self.isCurrent(token), self.isMutating else { return }
            self.deadlineWork = nil
            self.finishTimedOut(token: token)
        }
        requestRefresh(for: token)
    }

    /// Called by a window-manager event. Duplicate events collapse while a
    /// query is running or while an immediate query is already queued.
    func windowManagerDidChange(token: Int? = nil) {
        guard token.map({ isCurrent($0) }) ?? isCurrent(generation) else { return }
        scheduleEventRefresh(for: generation)
    }

    /// Called by an application-termination notification. It is only a
    /// trigger; the WM snapshot still decides whether the target disappeared.
    func applicationDidTerminate(
        processIdentifier: pid_t,
        bundleIdentifier: String?
    ) {
        guard case let .application(expectedPID, expectedBundle) = target,
              expectedPID == processIdentifier,
              expectedBundle == bundleIdentifier else {
            return
        }
        scheduleEventRefresh(for: generation)
    }

    private func requestRefresh(for token: Int, eventDriven: Bool = false) {
        guard isCurrent(token), let refresh else { return }
        if isMutating, elapsedTime >= Self.actionDeadline {
            finishTimedOut(token: token)
            guard eventDriven, isCurrent(token) else { return }
        }
        guard !refreshInFlight else {
            pendingEventRefresh = true
            return
        }

        pendingWork?.cancel()
        pendingWork = nil
        pendingWorkKind = nil
        refreshInFlight = true
        refresh { [weak self] result in
            let apply = {
                guard let self else { return }
                self.handleRefresh(result, token: token)
            }
            if Thread.isMainThread {
                apply()
            } else {
                DispatchQueue.main.async(execute: apply)
            }
        }
    }

    private func handleRefresh(
        _ result: AppSwitcherActionRefreshResult,
        token: Int
    ) {
        guard isCurrent(token) else { return }
        refreshInFlight = false

        if result == .targetGone {
            finishConfirmed(token: token)
            return
        }

        if pendingEventRefresh {
            pendingEventRefresh = false
            scheduleImmediateRefresh(for: token)
            return
        }

        if waitingForEvent {
            return
        }

        scheduleFallback(for: token)
    }

    private func scheduleImmediateRefresh(for token: Int) {
        guard isCurrent(token), pendingWork == nil else { return }
        pendingWorkKind = .event
        pendingWork = schedule(0) { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.pendingWork = nil
            self.pendingWorkKind = nil
            self.requestRefresh(for: token, eventDriven: true)
        }
    }

    private func scheduleEventRefresh(for token: Int) {
        guard isCurrent(token) else { return }
        if isMutating, elapsedTime >= Self.actionDeadline {
            finishTimedOut(token: token)
            guard isCurrent(token) else { return }
        }
        guard !refreshInFlight else {
            pendingEventRefresh = true
            return
        }
        guard pendingWorkKind != .event else { return }

        pendingWork?.cancel()
        pendingWork = nil
        pendingWorkKind = .event
        let delay = min(
            Self.eventDebounceDelay,
            max(0, Self.actionDeadline - elapsedTime)
        )
        pendingWork = schedule(delay) { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.pendingWork = nil
            self.pendingWorkKind = nil
            self.requestRefresh(for: token, eventDriven: true)
        }
    }

    private func scheduleFallback(for token: Int) {
        guard isCurrent(token) else { return }
        guard nextFallbackIndex < Self.refreshDelays.count else {
            // The target is still present after the bounded retries (for
            // example, an app kept a save prompt). Settle ownership without
            // treating it as absent so another action or Command release can
            // proceed while the row remains visible.
            finishTimedOut(token: token)
            return
        }

        let scheduledIndex = nextFallbackIndex
        let remaining = max(0, Self.refreshDelays[scheduledIndex] - elapsedTime)
        let delay = (remaining * 1_000).rounded() / 1_000
        pendingWork?.cancel()
        pendingWorkKind = .fallback
        pendingWork = schedule(delay) { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.pendingWork = nil
            self.pendingWorkKind = nil
            self.nextFallbackIndex = scheduledIndex + 1
            self.requestRefresh(for: token)
        }
    }

    private func finishConfirmed(token: Int) {
        guard isCurrent(token) else { return }
        pendingWork?.cancel()
        deadlineWork?.cancel()
        pendingWork = nil
        deadlineWork = nil
        pendingWorkKind = nil
        isMutating = false
        waitingForEvent = false
        target = nil
        refresh = nil
        refreshInFlight = false
        pendingEventRefresh = false
        let callback = onConfirmed
        onConfirmed = nil
        onTimedOut = nil
        callback?()
    }

    private func finishTimedOut(token: Int) {
        guard isCurrent(token) else { return }
        let hadPendingEvent = pendingWorkKind == .event || pendingEventRefresh
        pendingWork?.cancel()
        deadlineWork?.cancel()
        pendingWork = nil
        deadlineWork = nil
        pendingWorkKind = nil
        isMutating = false
        waitingForEvent = true
        pendingEventRefresh = hadPendingEvent && refreshInFlight
        let callback = onTimedOut
        onTimedOut = nil
        callback?()
        if hadPendingEvent, !refreshInFlight {
            scheduleImmediateRefresh(for: token)
        }
    }

    private func discardPassiveWait() {
        pendingWork?.cancel()
        deadlineWork?.cancel()
        pendingWork = nil
        deadlineWork = nil
        pendingWorkKind = nil
        waitingForEvent = false
        target = nil
        refresh = nil
        onConfirmed = nil
        onTimedOut = nil
        refreshInFlight = false
        pendingEventRefresh = false
    }

    private var elapsedTime: TimeInterval {
        max(0, now() - actionStartedAt)
    }
}
enum YabaiAppSwitcherTargetPolicy {
    static func check(
        _ scope: WMAppSwitcherTargetScope,
        rawWindows: [(id: Int, pid: pid_t)]
    ) -> WMAppSwitcherTargetResult {
        let liveIDs = Set(rawWindows.map(\.id))
        switch scope {
        case .window(let id):
            return WMAppSwitcherTargetResult(
                check: liveIDs.contains(id) ? .present : .absent,
                absentWindowManagerIDs: liveIDs.contains(id) ? [] : [id]
            )
        case .application(let processIdentifier, _, let windowManagerIDs):
            let present = rawWindows.contains {
                $0.pid == processIdentifier &&
                    (windowManagerIDs.isEmpty || windowManagerIDs.contains($0.id))
            }
            return WMAppSwitcherTargetResult(
                check: present ? .present : .absent,
                absentWindowManagerIDs: windowManagerIDs.subtracting(liveIDs)
            )
        }
    }
}

enum AppSwitcherActionSelectionPolicy {
    static func index(
        in windows: [SwitcherWindow],
        retaining windowID: Int?,
        nearestTo index: Int
    ) -> Int? {
        guard !windows.isEmpty else { return nil }
        if let windowID, let retainedIndex = windows.firstIndex(where: { $0.id == windowID }) {
            return retainedIndex
        }
        return min(index, windows.count - 1)
    }
}

enum AppSwitcherLeftShiftTapResult: Equatable {
    case ignored
    case consume
    case reverse
}

/// Recognizes a standalone left Shift tap while Cmd+Tab is open.
///
/// The policy keeps reverse intent separate from release suppression. The
/// event tap remains in charge of normal Cmd+Shift+Tab and all selection
/// movement, which prevents this opt-in shortcut from duplicating reverse
/// navigation.
struct AppSwitcherLeftShiftTapPolicy {
    static let leftShiftKeyCode: Int64 = 56
    static let rightShiftKeyCode: Int64 = 60

    private var awaitingRelease = false
    private var suppressLeftShiftRelease = false

    mutating func flagsChanged(
        keyCode: Int64,
        flags: CGEventFlags,
        enabled: Bool,
        switcherIsActive: Bool,
        rightShiftIsHeld: Bool = false
    ) -> AppSwitcherLeftShiftTapResult {
        let leftShiftReleased = keyCode == Self.leftShiftKeyCode &&
            (!flags.contains(.maskShift) || rightShiftIsHeld)
        if leftShiftReleased,
           suppressLeftShiftRelease {
            suppressLeftShiftRelease = false
            defer { awaitingRelease = false }
            return enabled && switcherIsActive && flags.contains(.maskCommand) && awaitingRelease
                ? .reverse
                : .consume
        }

        guard enabled, switcherIsActive else {
            reset()
            return .ignored
        }

        guard keyCode == Self.leftShiftKeyCode else {
            reset()
            return .ignored
        }

        guard flags.contains(.maskCommand) else {
            reset()
            return .ignored
        }

        if flags.contains(.maskShift) {
            guard !flags.contains(.maskControl),
                  !flags.contains(.maskAlternate),
                  !rightShiftIsHeld else {
                awaitingRelease = false
                return .ignored
            }
            awaitingRelease = true
            suppressLeftShiftRelease = true
            return .consume
        }

        guard awaitingRelease else { return .ignored }
        awaitingRelease = false
        return .reverse
    }

    mutating func keyPressedWhileHeld() {
        // Cmd+Shift+Tab and every other chord must use their normal handler.
        awaitingRelease = false
    }

    mutating func reset() {
        awaitingRelease = false
    }

    mutating func resetForTeardown() {
        awaitingRelease = false
        suppressLeftShiftRelease = false
    }
}
