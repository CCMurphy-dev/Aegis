//
//  RiftAdapter.swift
//  Aegis
//
//  Adapts RiftService to the WindowManagerProtocol.
//  Thin wrapper that delegates all operations to RiftService
//  and translates between Rift-specific types and WM-agnostic types.
//

import Foundation
import AppKit


final class RiftAdapter: WindowManagerProtocol {

    // MARK: - Identity

    let name = "Rift"
    let capabilities: WMCapabilities = [
        .floatWindows, .moveWindows, .toggleLayout
    ]

    // MARK: - Internal

    let eventRouter: EventRouter
    private var rift: RiftService

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter
        self.rift = RiftService(eventRouter: eventRouter)
    }

    // MARK: - Lifecycle

    func start() {
        // RiftService starts automatically on init
    }

    func stop() {
        rift.stop()
    }

    // MARK: - Queries — Spaces

    func getCurrentSpaces() -> [WMSpace] {
        return rift.getCurrentWorkspaces().map { $0.toWMSpace() }
    }

    func getSpacesForDisplay(_ displayIndex: Int) -> [WMSpace] {
        return rift.getWorkspacesForDisplay(displayIndex).map { $0.toWMSpace() }
    }

    func getFocusedSpace() -> WMSpace? {
        return rift.getFocusedWorkspace()?.toWMSpace()
    }

    func getFocusedSpaceIndex() -> Int {
        return rift.getFocusedWorkspaceIndex()
    }

    func spaceHasFocusedWindow(_ spaceIndex: Int) -> Bool {
        return rift.spaceHasFocusedWindow(spaceIndex)
    }

    // MARK: - Queries — Windows

    func getAllWindows() -> [WMWindow] {
        return rift.getAllWindows().compactMap { window in
            let wsIndex = window.windowServerId.flatMap { rift.getWindowSpace(Int($0)) }
            return window.toWMWindow(spaceIndex: wsIndex)
        }
    }

    func getWindowsForSpace(_ spaceIndex: Int) -> [WMWindow] {
        return rift.getWindowsForWorkspace(spaceIndex).compactMap { $0.toWMWindow(spaceIndex: spaceIndex) }
    }

    func getWindow(_ id: Int) -> WMWindow? {
        guard let window = rift.getWindow(id) else { return nil }
        return window.toWMWindow(spaceIndex: rift.getWindowSpace(id))
    }

    func checkAppSwitcherTarget(_ scope: WMAppSwitcherTargetScope) async -> WMAppSwitcherTargetResult {
        await rift.checkAppSwitcherTarget(scope)
    }

    func getWindowSpace(_ windowId: Int) -> Int? {
        return rift.getWindowSpace(windowId)
    }

    func getWindowIconsForSpace(_ spaceIndex: Int) -> [WindowIcon] {
        return rift.getWindowIconsForSpace(spaceIndex)
    }

    func getAppIconsForSpace(_ spaceIndex: Int) -> [NSImage] {
        return rift.getAppIconsForSpace(spaceIndex)
    }

    func getAppIcon(for appName: String) -> NSImage? {
        return rift.getAppIcon(for: appName)
    }

    // MARK: - Queries — Displays

    func getCurrentDisplays() -> [WMDisplay] {
        return rift.getCurrentDisplays().enumerated().map { (index, display) in
            display.toWMDisplay(index: index + 1)
        }
    }

    // MARK: - Commands — Focus

    func focusSpace(_ index: Int) {
        rift.focusWorkspace(index)
    }

    func focusWindow(_ id: Int) {
        rift.focusWindow(id)
    }

    func focusWindowByAppName(_ appName: String) -> Bool {
        return rift.focusWindowByAppName(appName)
    }

    // MARK: - Commands — Window Movement

    func moveWindow(_ id: Int, toSpace index: Int) {
        rift.moveWindow(id, toWorkspace: index)
    }

    func moveWindowAndFocus(_ id: Int, toSpace index: Int) {
        rift.moveWindow(id, toWorkspace: index)
        rift.focusWorkspace(index)
    }

    func moveWindowToSpace(_ windowId: Int, spaceIndex: Int, insertBeforeWindowId: Int?, shouldStack: Bool) {
        rift.moveWindow(windowId, toWorkspace: spaceIndex)
    }

    func moveWindowToSpaceFloatAndFocus(_ id: Int, spaceIndex: Int) {
        rift.moveWindow(id, toWorkspace: spaceIndex)
        rift.toggleFloat()
        rift.focusWorkspace(spaceIndex)
    }

    func floatAndCenterWindow(_ id: Int) {
        rift.toggleFloat()
    }

    func closeWindow(_ id: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        rift.executeRiftCli(args: WindowManagerCloseCommand.rift(id).arguments) { result in
            completion(result.map { _ in () })
        }
    }

    // MARK: - Commands — Space Management

    func createSpace() {
        rift.createWorkspace()
    }

    // MARK: - Commands — Layout

    func toggleLayout() {
        rift.toggleLayout()
    }

    // MARK: - Commands — Stacking

    func toggleStackAllWindows() {
        rift.toggleStackAllWindows()
    }

    func unstackWindows(_ windowIds: [Int]) {
        rift.unstackWindows(windowIds)
    }

    // MARK: - Raw Commands & Version

    func executeRawCommand(args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        rift.executeRiftCli(args: args, completion: completion)
    }

    func getVersion() -> String {
        return rift.getRiftVersion()
    }
}


// MARK: - Type Conversions

extension RiftWorkspace {
    func toWMSpace() -> WMSpace {
        WMSpace(
            id: index + 1,
            index: index + 1,
            display: 1,
            label: "\(index)",
            layoutType: WMLayoutType.fromRift(layoutMode),
            isFocused: isActive,
            isFullscreen: false
        )
    }
}

extension RiftWindow {
    func toWMWindow(spaceIndex: Int?) -> WMWindow? {
        guard let sysId = windowServerId else { return nil }
        return WMWindow(
            id: Int(sysId),
            pid: pid_t(id.pid),
            title: title,
            app: bundleId ?? appName ?? "Unknown",
            bundleIdentifier: bundleId,
            appName: appName ?? "Unknown",
            space: spaceIndex ?? 0,
            frame: frame.cgRect,
            hasFocus: isFocused,
            stackIndex: 0,
            isMinimized: false,
            isHidden: false,
            isVisible: true,
            isFloating: isFloating,
            isFullscreen: false
        )
    }
}

extension RiftDisplay {
    func toWMDisplay(index: Int) -> WMDisplay {
        WMDisplay(
            id: Int(screenId),
            uuid: uuid,
            index: index,
            frame: frame.cgRect,
            spaces: activeSpaceIds.map { Int($0) } + inactiveSpaceIds.map { Int($0) },
            hasFocus: isActiveContext
        )
    }
}

extension WMLayoutType {
    static func fromRift(_ mode: String) -> WMLayoutType {
        switch mode {
        case "bsp": return .bsp
        case "float": return .float
        case "stack": return .stack
        case "master_stack": return .masterStack
        case "scrolling": return .scrolling
        case "traditional": return .tiling
        default: return .unknown
        }
    }
}
