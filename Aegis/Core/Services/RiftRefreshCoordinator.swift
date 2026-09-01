import Foundation

/// The small amount of scheduling needed to serialize Rift refresh sequences.
///
/// The coordinator owns coalescing, debounce, and sequence generations. The
/// refresh action must call `finish` when its asynchronous work is complete.
/// Keeping this separate from RiftService makes the timing rules deterministic
/// to test without starting Rift or waiting on wall-clock timers.
final class RiftRefreshCoordinator {
    typealias RefreshAction = (
        _ scope: RiftRefreshScope,
        _ source: String,
        _ generation: UInt64,
        _ finish: @escaping () -> Void
    ) -> Void

    private let scheduler: any RiftRefreshScheduler
    private let refreshAction: RefreshAction
    private let coalesceDelay: TimeInterval
    private let debounceInterval: TimeInterval
    private let lock = NSLock()

    private var pendingScope: RiftRefreshScope = .none
    private var pendingSource = "unknown"
    private var scheduledStart: RiftRefreshScheduledTask?
    private var isRefreshing = false
    private var activeGeneration: UInt64?
    private var nextGeneration: UInt64 = 0
    private var lastStartTime: TimeInterval?
    private var stopped = false

    init(
        scheduler: any RiftRefreshScheduler = DispatchRiftRefreshScheduler(),
        coalesceDelay: TimeInterval = 0.03,
        debounceInterval: TimeInterval = 0.1,
        refreshAction: @escaping RefreshAction
    ) {
        self.scheduler = scheduler
        self.coalesceDelay = coalesceDelay
        self.debounceInterval = debounceInterval
        self.refreshAction = refreshAction
    }

    func request(scope: RiftRefreshScope, source: String = "unknown") {
        guard scope != .none else { return }

        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }

        pendingScope = pendingScope.merging(scope)
        pendingSource = source
        let shouldSchedule = !isRefreshing && scheduledStart == nil
        lock.unlock()

        if shouldSchedule {
            scheduleStart()
        }
    }

    /// Invalidate all in-flight work and prevent future requests from starting.
    func stop() {
        lock.lock()
        stopped = true
        pendingScope = .none
        scheduledStart?.cancel()
        scheduledStart = nil
        activeGeneration = nil
        isRefreshing = false
        nextGeneration &+= 1
        lock.unlock()
    }

    /// A refresh method checks this immediately before committing its result.
    func isCurrent(_ generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !stopped && activeGeneration == generation
    }

    private func scheduleStart() {
        lock.lock()
        guard !stopped, !isRefreshing, scheduledStart == nil, pendingScope != .none else {
            lock.unlock()
            return
        }

        let debounceRemaining: TimeInterval
        if let lastStartTime {
            debounceRemaining = max(0, lastStartTime + debounceInterval - scheduler.now)
        } else {
            debounceRemaining = 0
        }
        let delay = max(coalesceDelay, debounceRemaining)
        let task = scheduler.schedule(after: delay) { [weak self] in
            self?.startPendingRefresh()
        }
        scheduledStart = task
        lock.unlock()
    }

    private func startPendingRefresh() {
        lock.lock()
        scheduledStart = nil

        guard !stopped, !isRefreshing, pendingScope != .none else {
            lock.unlock()
            return
        }

        if let lastStartTime,
           scheduler.now - lastStartTime < debounceInterval {
            lock.unlock()
            scheduleStart()
            return
        }

        let scope = pendingScope
        let source = pendingSource
        pendingScope = .none
        nextGeneration &+= 1
        let generation = nextGeneration
        activeGeneration = generation
        isRefreshing = true
        lastStartTime = scheduler.now
        lock.unlock()

        refreshAction(scope, source, generation) { [weak self] in
            self?.finish(generation: generation)
        }
    }

    private func finish(generation: UInt64) {
        lock.lock()
        guard isRefreshing, activeGeneration == generation else {
            lock.unlock()
            return
        }
        isRefreshing = false
        activeGeneration = nil
        let shouldSchedule = !stopped && pendingScope != .none
        lock.unlock()

        if shouldSchedule {
            scheduleStart()
        }
    }
}

enum RiftRefreshOperation: Equatable {
    case displays
    case workspaces
}

enum RiftRefreshOperationPlan {
    static func operations(for scope: RiftRefreshScope) -> [RiftRefreshOperation] {
        switch scope {
        case .none:
            return []
        case .windowsOnly, .workspacesAndWindows:
            return [.workspaces]
        case .all:
            return [.displays, .workspaces]
        }
    }
}

/// Tracks delayed native-Space callbacks without tying them to DispatchQueue.
/// Starting a newer transition invalidates all callbacks from older ones.
final class RiftTransitionGenerationTracker {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var stopped = false

    func begin() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return generation
    }

    func isCurrent(_ candidate: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !stopped && generation == candidate
    }

    func stop() {
        lock.lock()
        stopped = true
        generation &+= 1
        lock.unlock()
    }
}

protocol RiftRefreshScheduler: AnyObject {
    var now: TimeInterval { get }
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> RiftRefreshScheduledTask
}

final class RiftRefreshScheduledTask {
    private let cancellation: () -> Void
    private var isCancelled = false
    private let lock = NSLock()

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        lock.unlock()
        cancellation()
    }
}

final class DispatchRiftRefreshScheduler: RiftRefreshScheduler {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> RiftRefreshScheduledTask {
        let work = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: .now() + max(0, delay), execute: work)
        return RiftRefreshScheduledTask { work.cancel() }
    }
}
