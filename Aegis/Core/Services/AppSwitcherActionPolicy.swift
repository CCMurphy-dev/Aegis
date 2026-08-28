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

    static func decision(
        for keyCode: Int64,
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
            return isPrintableKey(keyCode) ? .consume : .passThrough
        }

        // `:` is the one normal text entry in action mode. It always opens
        // the palette before W/Q are considered, including Cmd+Shift+;.
        if keyCode == semicolonKeyCode, flags.contains(.maskShift) {
            return .enterCommandPalette
        }

        let actionModifiers = flags.contains(.maskCommand) &&
            !flags.contains(.maskAlternate) &&
            !flags.contains(.maskControl) &&
            !flags.contains(.maskShift)

        if actionModifiers {
            switch keyCode {
            case wKeyCode: return isAutorepeat ? .consume : .perform(.close)
            case qKeyCode: return isAutorepeat ? .consume : .perform(.quit)
            default: break
            }
        }

        // Do not leak Cmd-printable shortcuts into the selected application
        // while action mode is open. Non-printable navigation still uses the
        // service's normal arrow, number, and escape handling.
        return isPrintableKey(keyCode) ? .consume : .passThrough
    }
}

/// Owns one app-switcher mutation and its bounded post-action refresh cycle.
///
/// A single token invalidates every queued callback when the switcher closes
/// or a newer action takes over. Callers only learn whether they may begin and
/// receive completion callbacks; scheduling details remain local here.
final class AppSwitcherActionRefreshCoordinator {
    static let refreshDelays: [TimeInterval] = [0, 0.15, 0.45]

    private var generation = 0
    private var isMutating = false
    private var pendingWork: [DispatchWorkItem] = []

    func begin() -> Int? {
        guard !isMutating else { return nil }
        generation += 1
        isMutating = true
        return generation
    }

    func cancel() {
        generation += 1
        pendingWork.forEach { $0.cancel() }
        pendingWork.removeAll()
        isMutating = false
    }

    func isCurrent(_ token: Int) -> Bool {
        token == generation && isMutating
    }

    func scheduleRefreshes(
        for token: Int,
        refresh: @escaping (@escaping () -> Void) -> Void
    ) {
        guard token == generation, isMutating else { return }
        runRefresh(token: token, attempt: 0, refresh: refresh)
    }

    private func runRefresh(
        token: Int,
        attempt: Int,
        refresh: @escaping (@escaping () -> Void) -> Void
    ) {
        guard token == generation, isMutating else { return }

        refresh { [weak self] in
            guard let self, token == self.generation, self.isMutating else { return }

            let nextAttempt = attempt + 1
            guard nextAttempt < Self.refreshDelays.count else {
                self.isMutating = false
                self.pendingWork.removeAll()
                return
            }

            let work = DispatchWorkItem { [weak self] in
                self?.runRefresh(token: token, attempt: nextAttempt, refresh: refresh)
            }
            self.pendingWork.append(work)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.refreshDelays[nextAttempt],
                execute: work
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
