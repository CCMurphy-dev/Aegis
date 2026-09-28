// Standalone regression test for ProcessRunner (no app host, no Accessibility).
// Run from the repo root:
//   swiftc -parse-as-library -default-isolation MainActor \
//     Aegis/Core/Services/ProcessRunner.swift Tests/ProcessRunnerTests.swift \
//     -o /tmp/aegis-process-runner-tests && /tmp/aegis-process-runner-tests

import Foundation

@main
struct ProcessRunnerTests {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL"): \(message)")
        if !condition { failures += 1 }
    }

    static func main() async {
        // Far more than a pipe buffer holds, on both streams.
        let bytes = 1_000_000
        let script = "head -c \(bytes) /dev/zero; head -c \(bytes) /dev/zero >&2; exit 3"
        do {
            let start = Date()
            let out = try await ProcessRunner.run("/bin/sh", ["-c", script], timeout: 10)
            check(out.stdout.count == bytes, "large stdout fully drained (\(out.stdout.count))")
            check(out.stderr.count == bytes, "large stderr fully drained (\(out.stderr.count))")
            check(out.status == 3, "exit status preserved (\(out.status))")
            check(Date().timeIntervalSince(start) < 5, "large output does not stall")
        } catch {
            check(false, "large output threw \(error)")
        }

        var start = Date()
        do {
            _ = try await ProcessRunner.run("/bin/sleep", ["30"], timeout: 0.5)
            check(false, "hung child should time out")
        } catch is ProcessRunner.TimeoutError {
            check(Date().timeIntervalSince(start) < 3, "hung child times out promptly")
        } catch {
            check(false, "unexpected error \(error)")
        }

        // Child ignores SIGTERM (builtins only, no grandchildren): runner must escalate to SIGKILL.
        start = Date()
        do {
            _ = try await ProcessRunner.run("/bin/sh", ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.5)
            check(false, "TERM-ignoring child should time out")
        } catch is ProcessRunner.TimeoutError {
            check(Date().timeIntervalSince(start) < 5, "TERM-ignoring child is killed")
        } catch {
            check(false, "unexpected error \(error)")
        }

        exit(failures == 0 ? 0 : 1)
    }
}
