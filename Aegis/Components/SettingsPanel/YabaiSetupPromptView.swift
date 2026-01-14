import SwiftUI
import AppKit

struct YabaiSetupPromptView: View {
    let status: YabaiSetupChecker.SetupStatus
    let onDismiss: () -> Void
    let onRetry: () -> Void

    @State private var copied = false

    private var setupCommand: String {
        // Use a predictable path for the setup script
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/aegis/setup-aegis-yabai.sh"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                Text("Yabai Setup Required")
                    .font(.headline)
                Spacer()
            }

            // Status message
            Text(statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("Run this command in Terminal:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Text(setupCommand)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .lineLimit(1)

                    Button(action: copyCommand) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .frame(width: 20)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy command")
                }
            }

            // Buttons
            HStack {
                Button("Open Terminal") {
                    openTerminal()
                }

                Button("Copy & Open Terminal") {
                    copyCommand()
                    openTerminal()
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Check Again") {
                    onRetry()
                }

                Button("Skip") {
                    onDismiss()
                }
                .foregroundColor(.secondary)
            }

            // Note about first-time setup
            Text("Note: The setup script requires sudo to install the notification helper.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            ensureSetupScriptExists()
        }
    }

    private var statusMessage: String {
        switch status {
        case .ready:
            return "Yabai integration is ready!"
        case .yabaiNotInstalled:
            return "Yabai window manager is not installed. Aegis uses yabai for space and window management. Install it first with: brew install koekeishiya/formulae/yabai"
        case .notifyScriptMissing:
            return "Aegis needs to install a helper script to receive events from yabai. Run the setup command below to configure everything."
        case .signalsNotConfigured:
            return "Yabai is installed but not configured to send events to Aegis. Run the setup command below to register the necessary signals."
        }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(setupCommand, forType: .string)
        copied = true

        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

    private func openTerminal() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    /// Ensure the setup script exists in ~/.config/aegis/
    private func ensureSetupScriptExists() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configDir = "\(home)/.config/aegis"
        let destPath = "\(configDir)/setup-aegis-yabai.sh"

        // Create config directory if needed
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        // Check if script already exists
        if FileManager.default.fileExists(atPath: destPath) {
            return
        }

        // Copy from bundle
        if let bundlePath = Bundle.main.path(forResource: "setup-aegis-yabai", ofType: "sh"),
           let contents = try? String(contentsOfFile: bundlePath, encoding: .utf8) {
            try? contents.write(toFile: destPath, atomically: true, encoding: .utf8)
            // Make executable
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
        }
    }
}

// MARK: - Window Controller for Setup Prompt

class YabaiSetupWindowController: NSWindowController {

    private var onDismiss: (() -> Void)?

    convenience init(status: YabaiSetupChecker.SetupStatus, onDismiss: @escaping () -> Void, onRetry: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Aegis Setup"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        self.onDismiss = onDismiss

        let view = YabaiSetupPromptView(
            status: status,
            onDismiss: { [weak self] in
                onDismiss()
                self?.close()
            },
            onRetry: { [weak self] in
                onRetry()
                self?.close()
            }
        )

        window.contentView = NSHostingView(rootView: view)
    }

    func showModal() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
