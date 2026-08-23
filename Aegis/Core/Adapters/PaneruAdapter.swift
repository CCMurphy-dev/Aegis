//
//  PaneruAdapter.swift
//  Aegis
//
//  Adapts PaneruService to the WindowManagerProtocol.
//  Thin wrapper that delegates all operations to PaneruService
//  and translates between Paneru-specific types and WM-agnostic types.
//

import Foundation
import AppKit


final class PaneruAdapter: WindowManagerProtocol {

    // MARK: - Identity

    let name = "Paneru"
    let capabilities: WMCapabilities = [
        .floatWindows, .moveWindows
    ]

    // MARK: - Internal

    let eventRouter: EventRouter
    private var paneru: PaneruService

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter
        self.paneru = PaneruService(eventRouter: eventRouter)
    }

    // MARK: - Lifecycle

    func start() {
        // PaneruService starts automatically on init
    }

    func stop() {
        paneru.stop()
    }

    // MARK: - Queries — Spaces

    func getCurrentSpaces() -> [WMSpace] {
        return paneru.getCurrentWorkspaces().map { $0.toWMSpace() }
    }

    func getSpacesForDisplay(_ displayIndex: Int) -> [WMSpace] {
        return paneru.getWorkspacesForDisplay(displayIndex).map { $0.toWMSpace() }
    }

    func getFocusedSpace() -> WMSpace? {
        return paneru.getFocusedWorkspace()?.toWMSpace()
    }

    func getFocusedSpaceIndex() -> Int {
        return paneru.getFocusedWorkspaceIndex()
    }

    func spaceHasFocusedWindow(_ spaceIndex: Int) -> Bool {
        return paneru.spaceHasFocusedWindow(spaceIndex)
    }

    // MARK: - Queries — Windows

    func getAllWindows() -> [WMWindow] {
        return paneru.getAllWindows().map { window in
            window.toWMWindow(spaceIndex: paneru.getWindowSpace(window.windowId))
        }
    }

    func getWindowsForSpace(_ spaceIndex: Int) -> [WMWindow] {
        return paneru.getWindowsForWorkspace(spaceIndex).map { $0.toWMWindow(spaceIndex: spaceIndex) }
    }

    func getWindow(_ id: Int) -> WMWindow? {
        guard let window = paneru.getWindow(id) else { return nil }
        return window.toWMWindow(spaceIndex: paneru.getWindowSpace(id))
    }

    func getWindowSpace(_ windowId: Int) -> Int? {
        return paneru.getWindowSpace(windowId)
    }

    func getWindowIconsForSpace(_ spaceIndex: Int) -> [WindowIcon] {
        return paneru.getWindowIconsForSpace(spaceIndex)
    }

    func getAppIconsForSpace(_ spaceIndex: Int) -> [NSImage] {
        return paneru.getAppIconsForSpace(spaceIndex)
    }

    func getAppIcon(for appName: String) -> NSImage? {
        return paneru.getAppIcon(for: appName)
    }

    // MARK: - Queries — Displays

    func getCurrentDisplays() -> [WMDisplay] {
        // Single-display scope (KISS) — synthesize one display from the main screen
        return [WMDisplay(
            id: 1,
            uuid: "1",
            index: 1,
            frame: NSScreen.main?.frame ?? .zero,
            spaces: getCurrentSpaces().map { $0.index },
            hasFocus: true
        )]
    }

    // MARK: - Commands — Focus

    func focusSpace(_ index: Int) {
        paneru.focusWorkspace(index)
    }

    func focusWindow(_ id: Int) {
        paneru.focusWindow(id)
    }

    func focusWindowByAppName(_ appName: String) -> Bool {
        return paneru.focusWindowByAppName(appName)
    }

    // MARK: - Commands — Window Movement

    func moveWindow(_ id: Int, toSpace index: Int) {
        paneru.moveWindow(id, toWorkspace: index)
    }

    func moveWindowAndFocus(_ id: Int, toSpace index: Int) {
        paneru.moveWindowAndFocus(id, toWorkspace: index)
    }

    func moveWindowToSpace(_ windowId: Int, spaceIndex: Int, insertBeforeWindowId: Int?, shouldStack: Bool) {
        paneru.moveWindow(windowId, toWorkspace: spaceIndex)
    }

    // MARK: - Commands — Layout

    func toggleLayout() {
        // Paneru is scrolling-only — no layout toggle
    }

    // MARK: - Raw Commands & Version

    func executeRawCommand(args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        paneru.executePaneruCommand(args: args, completion: completion)
    }

    func getVersion() -> String {
        return paneru.getPaneruVersion()
    }
}


// MARK: - Type Conversions

extension PaneruVirtualWorkspace {
    func toWMSpace() -> WMSpace {
        WMSpace(
            id: number,
            index: number,
            display: 1,
            label: nil,                 // UI falls back to showing the index
            layoutType: .scrolling,
            isFocused: active,
            isFullscreen: false
        )
    }
}

extension PaneruWindow {
    func toWMWindow(spaceIndex: Int?) -> WMWindow {
        // Resolve PID from bundle ID — needed for AXObserver (window title tracking)
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first?.processIdentifier ?? 0

        return WMWindow(
            id: windowId,
            pid: pid,
            title: title,
            app: bundleId,
            appName: appName,
            space: spaceIndex ?? 0,
            frame: nil,
            hasFocus: focused,
            stackIndex: 0,
            isMinimized: false,
            isHidden: false,
            isVisible: true,
            isFloating: floating,
            isFullscreen: false
        )
    }
}
