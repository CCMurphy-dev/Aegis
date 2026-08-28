//
//  AeroSpaceAdapter.swift
//  Aegis
//
//  Adapts AeroSpaceService to the WindowManagerProtocol.
//  AeroSpace uses string-named virtual workspaces mapped to sequential 1-based indices.
//

import Foundation
import AppKit


final class AeroSpaceAdapter: WindowManagerProtocol {

    // MARK: - Identity

    let name = "AeroSpace"
    let capabilities: WMCapabilities = [
        .floatWindows, .moveWindows, .toggleLayout, .balanceLayout
    ]

    // MARK: - Internal

    let eventRouter: EventRouter
    private var aero: AeroSpaceService

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter
        self.aero = AeroSpaceService(eventRouter: eventRouter)
    }

    // MARK: - Lifecycle

    func start() {
        // AeroSpaceService starts automatically on init
    }

    func stop() {
        aero.stop()
    }

    // MARK: - Queries — Spaces

    func getCurrentSpaces() -> [WMSpace] {
        return aero.getCurrentWorkspaces().map { ws in
            WMSpace(
                id: ws.index,
                index: ws.index,
                display: 1,
                label: ws.name,
                layoutType: .tiling,   // AeroSpace doesn't expose per-workspace layout in queries
                isFocused: ws.isFocused,
                isFullscreen: false
            )
        }
    }

    func getSpacesForDisplay(_ displayIndex: Int) -> [WMSpace] {
        return getCurrentSpaces()
    }

    func getFocusedSpace() -> WMSpace? {
        return getCurrentSpaces().first(where: { $0.isFocused })
    }

    func getFocusedSpaceIndex() -> Int {
        return aero.getFocusedWorkspaceIndex()
    }

    func spaceHasFocusedWindow(_ spaceIndex: Int) -> Bool {
        return aero.spaceHasFocusedWindow(spaceIndex)
    }

    // MARK: - Queries — Windows

    func getAllWindows() -> [WMWindow] {
        let focusedId = aero.getFocusedWindowId()
        return aero.getAllASWindows().compactMap { window in
            let wsIndex = aero.getWindowSpace(window.windowId)
            var wmWin = window.toWMWindow(spaceIndex: wsIndex)
            if window.windowId == focusedId {
                wmWin = WMWindow(
                    id: wmWin.id, pid: wmWin.pid, title: wmWin.title,
                    app: wmWin.app, bundleIdentifier: wmWin.bundleIdentifier,
                    appName: wmWin.appName, space: wmWin.space,
                    frame: wmWin.frame, hasFocus: true, stackIndex: wmWin.stackIndex,
                    isMinimized: wmWin.isMinimized, isHidden: wmWin.isHidden,
                    isVisible: wmWin.isVisible, isFloating: wmWin.isFloating,
                    isFullscreen: wmWin.isFullscreen
                )
            }
            return wmWin
        }
    }

    func getWindowsForSpace(_ spaceIndex: Int) -> [WMWindow] {
        return aero.getWindowsForWorkspace(spaceIndex).compactMap { $0.toWMWindow(spaceIndex: spaceIndex) }
    }

    func getWindow(_ id: Int) -> WMWindow? {
        guard let window = aero.getWindow(id) else { return nil }
        return window.toWMWindow(spaceIndex: aero.getWindowSpace(id))
    }

    func getWindowSpace(_ windowId: Int) -> Int? {
        return aero.getWindowSpace(windowId)
    }

    func getWindowIconsForSpace(_ spaceIndex: Int) -> [WindowIcon] {
        return aero.getWindowIconsForSpace(spaceIndex)
    }

    func getAppIconsForSpace(_ spaceIndex: Int) -> [NSImage] {
        return aero.getAppIconsForSpace(spaceIndex)
    }

    func getAppIcon(for appName: String) -> NSImage? {
        return aero.getAppIcon(for: appName)
    }

    // MARK: - Queries — Displays

    func getCurrentDisplays() -> [WMDisplay] {
        return aero.getCurrentMonitors().map { monitor in
            WMDisplay(
                id: monitor.monitorId,
                uuid: "\(monitor.monitorId)",
                index: monitor.monitorId,
                frame: NSScreen.main?.frame ?? .zero,
                spaces: getCurrentSpaces().map { $0.index },
                hasFocus: true
            )
        }
    }

    // MARK: - Commands — Focus

    func focusSpace(_ index: Int) {
        aero.focusWorkspace(index)
    }

    func focusWindow(_ id: Int) {
        aero.focusWindow(id)
    }

    func focusWindowByAppName(_ appName: String) -> Bool {
        return aero.focusWindowByAppName(appName)
    }

    // MARK: - Commands — Window Movement

    func moveWindow(_ id: Int, toSpace index: Int) {
        aero.moveWindow(id, toWorkspace: index)
    }

    func moveWindowAndFocus(_ id: Int, toSpace index: Int) {
        aero.moveWindowAndFocus(id, toWorkspace: index)
    }

    func moveWindowToSpace(_ windowId: Int, spaceIndex: Int, insertBeforeWindowId: Int?, shouldStack: Bool) {
        aero.moveWindow(windowId, toWorkspace: spaceIndex)
    }

    func closeWindow(_ id: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        aero.executeRawCommand(args: WindowManagerCloseCommand.aeroSpace(id).arguments) { result in
            completion(result.map { _ in () })
        }
    }

    // MARK: - Commands — Space Management

    func createSpace() {
        aero.createWorkspace()
    }

    // MARK: - Commands — Layout

    func toggleLayout() {
        aero.toggleLayout()
    }

    func balanceLayout() {
        aero.balanceSizes()
    }

    // MARK: - Raw Commands & Version

    func executeRawCommand(args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        aero.executeRawCommand(args: args, completion: completion)
    }

    func getVersion() -> String {
        return aero.getVersion()
    }
}


// MARK: - Type Conversions

extension ASWindow {
    func toWMWindow(spaceIndex: Int?) -> WMWindow {
        let owner = AeroSpaceWindowOwnerPolicy.resolve(
            bundleIdentifier: appBundleId,
            processIdentifiers: appBundleId.map {
                NSRunningApplication.runningApplications(withBundleIdentifier: $0)
                    .map(\.processIdentifier)
            } ?? []
        )

        return WMWindow(
            id: windowId,
            pid: owner.pid,
            title: windowTitle,
            app: appBundleId ?? appName,
            bundleIdentifier: owner.bundleIdentifier,
            appName: appName,
            space: spaceIndex ?? 0,
            frame: nil,
            hasFocus: false,         // Set by adapter based on focused window query
            stackIndex: 0,
            isMinimized: false,
            isHidden: false,
            isVisible: true,
            isFloating: false,       // AeroSpace doesn't expose floating state in list-windows
            isFullscreen: false
        )
    }
}

struct AeroSpaceWindowOwner: Equatable {
    let pid: pid_t
    let bundleIdentifier: String?
}

enum AeroSpaceWindowOwnerPolicy {
    static func resolve(
        bundleIdentifier: String?,
        processIdentifiers: [pid_t]
    ) -> AeroSpaceWindowOwner {
        guard let bundleIdentifier, processIdentifiers.count == 1,
              let pid = processIdentifiers.first else {
            return AeroSpaceWindowOwner(pid: 0, bundleIdentifier: nil)
        }
        return AeroSpaceWindowOwner(pid: pid, bundleIdentifier: bundleIdentifier)
    }
}
