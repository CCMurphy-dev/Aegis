//
//  ProcessRunner.swift
//  Aegis
//
//  Runs a short-lived CLI subprocess without deadlocking on full pipes.
//  stdout/stderr are drained while the child runs, and the child is
//  terminated if it exceeds the timeout.
//

import Foundation

nonisolated enum ProcessRunner {
    struct Output: Sendable {
        let status: Int32
        let stdout: Data
        let stderr: Data
    }

    struct TimeoutError: LocalizedError {
        let executable: String
        let timeout: TimeInterval
        var errorDescription: String? { "\(executable) timed out after \(timeout)s" }
    }

    /// Runs the process on a background queue so callers never block a cooperative thread.
    static func run(_ executable: String, _ args: [String], timeout: TimeInterval) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try runBlocking(executable, args, timeout: timeout) })
            }
        }
    }

    static func runBlocking(_ executable: String, _ args: [String], timeout: TimeInterval) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        let drained = DispatchGroup()
        let stdoutBuffer = drain(stdoutPipe, into: drained)
        let stderrBuffer = drain(stderrPipe, into: drained)

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
        }

        // EOF normally arrives right after exit; don't hang if a grandchild kept the pipe open.
        _ = drained.wait(timeout: .now() + 1)
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        if timedOut {
            throw TimeoutError(executable: executable, timeout: timeout)
        }
        return Output(status: process.terminationStatus, stdout: stdoutBuffer.data, stderr: stderrBuffer.data)
    }

    private final class Buffer: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()
        private var finished = false

        func append(_ chunk: Data) { lock.withLock { storage.append(chunk) } }
        var data: Data { lock.withLock { storage } }

        /// Returns true only on the first call.
        func finish() -> Bool {
            lock.withLock {
                defer { finished = true }
                return !finished
            }
        }
    }

    private static func drain(_ pipe: Pipe, into group: DispatchGroup) -> Buffer {
        let buffer = Buffer()
        group.enter()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                if buffer.finish() { group.leave() }
            } else {
                buffer.append(chunk)
            }
        }
        return buffer
    }
}
