import SwiftUI
import AppKit

struct AeroSpaceSetupPromptView: View {
    let status: AeroSpaceSetupChecker.SetupStatus
    let onDismiss: () -> Void
    let onRetry: () -> Void

    @State private var copied = false

    private var setupCommand: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/aegis/setup-aegis-aerospace.sh"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                Text("AeroSpace Setup Required")
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

            // Note
            Text("Note: The setup script will create files in ~/.config/aegis/ and optionally add a line to your .aerospace.toml.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            ensureIntegrationFilesExist()
        }
    }

    private var statusMessage: String {
        switch status {
        case .ready:
            return "AeroSpace integration is ready!"
        case .aeroSpaceNotInstalled:
            return "AeroSpace window manager is not installed. Install it first with: brew install --cask nikitabobko/tap/aerospace"
        case .notifyScriptMissing:
            return "Aegis needs to install a helper script to receive events from AeroSpace. Run the setup command below to configure everything."
        case .configNotSetUp:
            return "AeroSpace is installed but not configured to notify Aegis on workspace changes. Run the setup command below to add the integration."
        }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(setupCommand, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

    private func openTerminal() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    /// Copy all integration scripts from the app bundle to ~/.config/aegis/,
    /// overwriting any file whose content differs from the bundled version.
    /// This ensures scripts are updated automatically after an app upgrade.
    private func ensureIntegrationFilesExist() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configDir = "\(home)/.config/aegis"
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        let resources: [(resource: String, ext: String?, dest: String)] = [
            ("setup-aegis-aerospace",    "sh", "\(configDir)/setup-aegis-aerospace.sh"),
            ("aegis-aerospace-notify",   nil,  "\(configDir)/aegis-aerospace-notify"),
            ("aegis-aerospace-mode-notify", nil, "\(configDir)/aegis-aerospace-mode-notify"),
        ]

        for (resource, ext, destPath) in resources {
            guard let bundlePath = Bundle.main.path(forResource: resource, ofType: ext),
                  let bundleContent = try? String(contentsOfFile: bundlePath, encoding: .utf8) else {
                continue
            }
            let existingContent = try? String(contentsOfFile: destPath, encoding: .utf8)
            guard existingContent != bundleContent else { continue }  // already up to date
            try? bundleContent.write(toFile: destPath, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
        }
    }
}

// MARK: - Window Controller for Setup Prompt

class AeroSpaceSetupWindowController: NSWindowController {

    private var onDismiss: (() -> Void)?

    convenience init(status: AeroSpaceSetupChecker.SetupStatus, onDismiss: @escaping () -> Void, onRetry: @escaping () -> Void) {
        let window = AegisOverlayWindow(
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

        let view = AeroSpaceSetupPromptView(
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
