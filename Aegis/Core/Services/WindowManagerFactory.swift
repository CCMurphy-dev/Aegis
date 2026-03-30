//
//  WindowManagerFactory.swift
//  Aegis
//
//  Creates the appropriate WindowManagerProtocol adapter based on config.
//

import Cocoa


enum WindowManagerType: String, Codable, CaseIterable {
    case auto
    case yabai
    case rift
    case aerospace

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .yabai: return "Yabai"
        case .rift: return "Rift"
        case .aerospace: return "AeroSpace"
        }
    }

    var description: String {
        switch self {
        case .auto: return "Detects which window manager is running"
        case .yabai: return "Tiling WM with BSP, float, and stack layouts"
        case .rift: return "Tiling WM with BSP, master-stack, and scrolling layouts"
        case .aerospace: return "Tiling WM inspired by i3"
        }
    }
}


struct WindowManagerFactory {

    /// Create the window manager adapter based on the configured type.
    static func create(type: WindowManagerType, eventRouter: EventRouter) -> WindowManagerProtocol {
        switch type {
        case .yabai:
            return YabaiAdapter(eventRouter: eventRouter)
        case .rift:
            return RiftAdapter(eventRouter: eventRouter)
        case .aerospace:
            return AeroSpaceAdapter(eventRouter: eventRouter)
        case .auto:
            return autoDetect(eventRouter: eventRouter)
        }
    }

    /// Auto-detect which window manager is running by checking for their processes.
    private static func autoDetect(eventRouter: EventRouter) -> WindowManagerProtocol {
        let runningApps = NSWorkspace.shared.runningApplications.map { $0.localizedName ?? "" }

        // Check in priority order
        if runningApps.contains("yabai") || isProcessRunning("yabai") {
            logInfo("Auto-detected window manager: Yabai")
            return YabaiAdapter(eventRouter: eventRouter)
        }

        if isProcessRunning("rift") {
            logInfo("Auto-detected window manager: Rift")
            return RiftAdapter(eventRouter: eventRouter)
        }

        if runningApps.contains("AeroSpace") || isProcessRunning("AeroSpace") {
            logInfo("Auto-detected window manager: AeroSpace")
            return AeroSpaceAdapter(eventRouter: eventRouter)
        }

        logInfo("No window manager detected, defaulting to Yabai")
        return YabaiAdapter(eventRouter: eventRouter)
    }

    private static func isProcessRunning(_ name: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", name]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
