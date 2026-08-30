//
//  YabaiCommandActor.swift
//  Aegis
//
//  Created by Christopher Murphy on 13/01/2026.
//
import Foundation
import AppKit   // Only needed if you're using NSImage, NSWorkspace, etc.

struct YabaiCLIResult {
    let output: String
    let terminationStatus: Int32
}

enum YabaiCLIExecutionPolicy {
    static func result(_ response: YabaiCLIResult) -> Result<String, Error> {
        guard response.terminationStatus == 0 else {
            let message = response.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(NSError(
                domain: "YabaiService",
                code: Int(response.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey:
                    message.isEmpty ? "yabai failed" : message]
            ))
        }
        return .success(response.output)
    }
}

actor YabaiCommandActor {

    static let shared = YabaiCommandActor()

    private let yabaiPath = "/opt/homebrew/bin/yabai"
    private var lastRun = Date.distantPast
    private let minInterval: TimeInterval = 0.05 // 50ms between commands (max 20/sec)
    private var activeProcessCount = 0
    private let maxConcurrentProcesses = 3  // Limit concurrent yabai processes

    func run(_ args: [String]) async throws -> String {
        (try await runWithStatus(args)).output
    }

    func runWithStatus(_ args: [String]) async throws -> YabaiCLIResult {
        // Wait if too many processes are active
        while activeProcessCount >= maxConcurrentProcesses {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Throttle: ensure minimum interval between starts
        let now = Date()
        let delta = now.timeIntervalSince(lastRun)
        if delta < minInterval {
            try await Task.sleep(nanoseconds: UInt64((minInterval - delta) * 1_000_000_000))
        }
        lastRun = Date()

        // Track active process
        activeProcessCount += 1

        // Execute process
        let result: YabaiCLIResult
        do {
            result = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: self.yabaiPath)
                        process.arguments = args

                        let pipe = Pipe()
                        process.standardOutput = pipe
                        process.standardError = pipe

                        try process.run()
                        process.waitUntilExit()

                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(decoding: data, as: UTF8.self)
                        continuation.resume(returning: YabaiCLIResult(
                            output: output,
                            terminationStatus: process.terminationStatus
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            // Decrement on error before re-throwing
            activeProcessCount -= 1
            throw error
        }

        // Decrement on success
        activeProcessCount -= 1
        return result
    }
}
