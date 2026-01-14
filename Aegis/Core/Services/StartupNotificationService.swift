import Foundation
import UserNotifications

class StartupNotificationService: NSObject, UNUserNotificationCenterDelegate {

    private static let shared = StartupNotificationService()

    static func showStartupNotification() {
        // Get versions and status
        let aegisVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let status = YabaiSetupChecker.check()

        let title = "Aegis v\(aegisVersion)"
        var lines: [String] = []

        switch status {
        case .ready:
            let yabaiVersion = getYabaiVersion()
            lines.append("Yabai: v\(yabaiVersion)")
            lines.append("Link: Active")
        case .yabaiNotInstalled:
            lines.append("Yabai: Not installed")
            lines.append("Link: Inactive")
        case .signalsNotConfigured:
            let yabaiVersion = getYabaiVersion()
            lines.append("Yabai: v\(yabaiVersion)")
            lines.append("Link: Not configured")
        case .notifyScriptMissing:
            let yabaiVersion = getYabaiVersion()
            lines.append("Yabai: v\(yabaiVersion)")
            lines.append("Link: Script missing")
        }

        let body = lines.joined(separator: "\n")

        print("📬 Notification content: \(title) - \(body)")

        // Set delegate to allow notifications while app is in foreground
        UNUserNotificationCenter.current().delegate = shared

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("⚠️ Notification permission error: \(error)")
                return
            }

            guard granted else {
                print("⚠️ Notification permission not granted")
                return
            }

            // Dispatch to main thread and create content there
            DispatchQueue.main.async {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default

                // Use a short delay trigger instead of immediate
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
                let identifier = "aegis.startup.\(Date().timeIntervalSince1970)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("⚠️ Failed to add notification: \(error)")
                    } else {
                        print("✅ Startup notification sent: \(body)")
                    }
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Allow notifications to show even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Helpers

    private static func getYabaiVersion() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yabai")
        task.arguments = ["--version"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            // Extract just the version number (e.g., "yabai-v7.1.0" -> "7.1.0")
            if let match = output.range(of: #"v?(\d+\.\d+\.\d+)"#, options: .regularExpression) {
                return String(output[match]).replacingOccurrences(of: "v", with: "")
            }
            return output.isEmpty ? "?" : output
        } catch {
            return "?"
        }
    }
}
