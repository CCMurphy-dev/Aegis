import Foundation
import AppKit

// MARK: - Command Model

struct PaletteCommand: Identifiable {
    let id: String
    let label: String
    let description: String
    let icon: String          // SF Symbol name
    let category: String
    let action: () -> Void
}

// MARK: - Command Registry

final class CommandRegistry {

    private weak var windowManager: WindowManagerProtocol?
    private let config = AegisConfig.shared

    /// Window ID that was selected in the app switcher when command mode was entered
    var focusedWindowId: Int?

    init(windowManager: WindowManagerProtocol?) {
        self.windowManager = windowManager
    }

    /// Build full command list from WM capabilities + custom commands
    func allCommands() -> [PaletteCommand] {
        var commands: [PaletteCommand] = []
        commands.append(contentsOf: builtInCommands())
        commands.append(contentsOf: customCommands())
        return commands
    }

    /// Filter commands by query (fuzzy match on label + description)
    func filter(_ commands: [PaletteCommand], query: String) -> [PaletteCommand] {
        guard !query.isEmpty else { return commands }
        let q = query.lowercased()
        return commands.filter {
            $0.label.lowercased().contains(q) ||
            $0.description.lowercased().contains(q) ||
            $0.category.lowercased().contains(q)
        }
    }

    // MARK: - Built-in Commands

    private func builtInCommands() -> [PaletteCommand] {
        guard let wm = windowManager else { return [] }
        let caps = wm.capabilities
        var cmds: [PaletteCommand] = []

        // Focus space 1-9
        for i in 1...9 {
            cmds.append(PaletteCommand(
                id: "focus-space-\(i)",
                label: "Focus Space \(i)",
                description: "Switch to space \(i)",
                icon: "square.grid.2x2",
                category: "Space"
            ) { [weak wm] in wm?.focusSpace(i) })
        }

        // Move focused window to space 1-9
        if caps.contains(.moveWindows), let windowId = focusedWindowId {
            for i in 1...9 {
                cmds.append(PaletteCommand(
                    id: "move-to-space-\(i)",
                    label: "Move to Space \(i)",
                    description: "Move window to space \(i)",
                    icon: "arrow.forward.square",
                    category: "Window"
                ) { [weak wm] in wm?.moveWindowAndFocus(windowId, toSpace: i) })
            }
        }

        // Layout commands
        if caps.contains(.toggleLayout) {
            cmds.append(PaletteCommand(
                id: "toggle-layout",
                label: "Toggle Layout",
                description: "Switch between BSP and float",
                icon: "rectangle.split.2x2",
                category: "Layout"
            ) { [weak wm] in wm?.toggleLayout() })
        }

        if caps.contains(.rotateLayout) {
            for deg in [90, 180, 270] {
                cmds.append(PaletteCommand(
                    id: "rotate-\(deg)",
                    label: "Rotate \(deg)\u{00B0}",
                    description: "Rotate layout tree \(deg) degrees",
                    icon: "rotate.right",
                    category: "Layout"
                ) { [weak wm] in wm?.rotateLayout(deg) })
            }
        }

        if caps.contains(.balanceLayout) {
            cmds.append(PaletteCommand(
                id: "balance",
                label: "Balance Layout",
                description: "Equalize window sizes",
                icon: "equal.square",
                category: "Layout"
            ) { [weak wm] in wm?.balanceLayout() })
        }

        if caps.contains(.flipLayout) {
            cmds.append(PaletteCommand(
                id: "flip-x",
                label: "Flip Horizontal",
                description: "Mirror layout along X axis",
                icon: "arrow.left.arrow.right",
                category: "Layout"
            ) { [weak wm] in wm?.flipLayout(axis: "x") })

            cmds.append(PaletteCommand(
                id: "flip-y",
                label: "Flip Vertical",
                description: "Mirror layout along Y axis",
                icon: "arrow.up.arrow.down",
                category: "Layout"
            ) { [weak wm] in wm?.flipLayout(axis: "y") })
        }

        // Space management
        if caps.contains(.createSpace) {
            cmds.append(PaletteCommand(
                id: "create-space",
                label: "Create Space",
                description: "Add a new space",
                icon: "plus.square",
                category: "Space"
            ) { [weak wm] in wm?.createSpace() })
        }

        if caps.contains(.stackWindows) {
            cmds.append(PaletteCommand(
                id: "stack-all",
                label: "Stack All Windows",
                description: "Stack all windows on current space",
                icon: "square.stack.3d.up",
                category: "Window"
            ) { [weak wm] in wm?.toggleStackAllWindows() })
        }

        return cmds
    }

    // MARK: - Custom Commands from Config

    private func customCommands() -> [PaletteCommand] {
        return config.customCommands.enumerated().map { index, cmd in
            let label = cmd["label"] ?? "Custom \(index + 1)"
            let command = cmd["command"] ?? ""
            let icon = cmd["icon"] ?? "terminal"
            let description = cmd["description"] ?? command

            return PaletteCommand(
                id: "custom-\(index)",
                label: label,
                description: description,
                icon: icon,
                category: "Custom"
            ) {
                guard !command.isEmpty else { return }
                Task.detached {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    process.arguments = ["-c", command]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    try? process.run()
                }
            }
        }
    }
}
