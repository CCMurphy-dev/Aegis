//
//  YabaiAdapter.swift
//  Aegis
//
//  Adapts YabaiService to the WindowManagerProtocol.
//  This is a thin wrapper that delegates all operations to the existing
//  YabaiService and translates between yabai-specific types and WM-agnostic types.
//

import Foundation
import AppKit


final class YabaiAdapter: WindowManagerProtocol {

    // MARK: - Identity

    let name = "Yabai"
    let capabilities: WMCapabilities = .all

    // MARK: - Internal

    let eventRouter: EventRouter
    private var yabai: YabaiService

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter
        self.yabai = YabaiService(eventRouter: eventRouter)
    }

    // MARK: - Lifecycle

    func start() {
        // YabaiService starts automatically on init (FIFO + initial refresh)
    }

    func stop() {
        // YabaiService cleans up in deinit
    }

    // MARK: - Queries — Spaces

    func getCurrentSpaces() -> [WMSpace] {
        return yabai.getCurrentSpaces().map { $0.toWMSpace() }
    }

    func getSpacesForDisplay(_ displayIndex: Int) -> [WMSpace] {
        return yabai.getSpacesForDisplay(displayIndex).map { $0.toWMSpace() }
    }

    func getFocusedSpace() -> WMSpace? {
        return yabai.getFocusedSpaceSync()?.toWMSpace()
    }

    func getFocusedSpaceIndex() -> Int {
        return yabai.getFocusedSpaceIndexSync()
    }

    func spaceHasFocusedWindow(_ spaceIndex: Int) -> Bool {
        return yabai.spaceHasFocusedWindow(spaceIndex)
    }

    // MARK: - Queries — Windows

    func getAllWindows() -> [WMWindow] {
        return yabai.getAllWindows().map { $0.toWMWindow() }
    }

    func getWindowsForSpace(_ spaceIndex: Int) -> [WMWindow] {
        return yabai.queryWindowsForSpaceSync(spaceIndex)
            .map { $0.toWMWindow() }
    }

    func getWindow(_ id: Int) -> WMWindow? {
        return yabai.getWindow(id)?.toWMWindow()
    }

    func getWindowSpace(_ windowId: Int) -> Int? {
        return yabai.getWindowSpace(windowId)
    }

    func getWindowIconsForSpace(_ spaceIndex: Int) -> [WindowIcon] {
        return yabai.getWindowIconsForSpace(spaceIndex)
    }

    func getAppIconsForSpace(_ spaceIndex: Int) -> [NSImage] {
        return yabai.getAppIconsForSpace(spaceIndex)
    }

    func getAppIcon(for appName: String) -> NSImage? {
        return yabai.getAppIcon(for: appName)
    }

    // MARK: - Queries — Displays

    func getCurrentDisplays() -> [WMDisplay] {
        return yabai.getCurrentDisplays().map { $0.toWMDisplay() }
    }

    // MARK: - Commands — Focus

    func focusSpace(_ index: Int) {
        yabai.focusSpace(index)
    }

    func focusWindow(_ id: Int) {
        yabai.focusWindow(id)
    }

    func focusWindowByAppName(_ appName: String) -> Bool {
        return yabai.focusWindowByAppName(appName)
    }

    // MARK: - Commands — Window Movement

    func moveWindow(_ id: Int, toSpace index: Int) {
        yabai.moveWindow(id, toSpace: index)
    }

    func moveWindowAndFocus(_ id: Int, toSpace index: Int) {
        yabai.moveWindowToSpaceAndFocus(id, spaceIndex: index)
    }

    func moveWindowToSpace(_ windowId: Int, spaceIndex: Int, insertBeforeWindowId: Int?, shouldStack: Bool) {
        yabai.moveWindowToSpace(windowId, spaceIndex: spaceIndex, insertBeforeWindowId: insertBeforeWindowId, shouldStack: shouldStack)
    }

    func moveWindowToSpaceFloatAndFocus(_ id: Int, spaceIndex: Int) {
        yabai.moveWindowToSpaceFloatAndFocus(id, spaceIndex: spaceIndex)
    }

    func floatAndCenterWindow(_ id: Int) {
        yabai.floatAndCenterWindow(id)
    }

    // MARK: - Commands — Space Management

    func createSpace() {
        yabai.createSpace()
    }

    func destroySpace(_ index: Int) {
        yabai.destroySpace(index)
    }

    func moveSpace(from: Int, to: Int) {
        yabai.moveSpace(from, toIndex: to)
    }

    // MARK: - Commands — Layout

    func toggleLayout() {
        yabai.toggleLayout()
    }

    func rotateLayout(_ degrees: Int) {
        yabai.rotateLayout(degrees)
    }

    func balanceLayout() {
        yabai.balanceLayout()
    }

    func flipLayout(axis: String) {
        yabai.flipLayout(axis: axis)
    }

    // MARK: - Commands — Stacking

    func toggleStackAllWindows() {
        yabai.toggleStackAllWindowsInCurrentSpace()
    }

    func stackWindow(_ sourceId: Int, onto targetId: Int) {
        yabai.stackWindow(sourceId, onto: targetId)
    }

    func unstackWindows(_ windowIds: [Int]) {
        yabai.unstackWindows(windowIds)
    }

    func stackAllWindowsOnto(_ targetId: Int) {
        yabai.stackAllWindowsOnto(targetId)
    }

    // MARK: - Raw Commands & Version

    func executeRawCommand(args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        yabai.executeYabai(args: args, completion: completion)
    }

    func getVersion() -> String {
        return yabai.getYabaiVersion()
    }
}


// MARK: - Type Conversions

extension Space {
    func toWMSpace() -> WMSpace {
        WMSpace(
            id: id,
            index: index,
            display: display,
            label: label,
            workspaceName: label,
            layoutType: WMLayoutType.fromYabai(type),
            isFocused: focused,
            isFullscreen: isNativeFullscreen
        )
    }
}

extension WindowInfo {
    func toWMWindow() -> WMWindow {
        WMWindow(
            id: id,
            pid: pid,
            title: title,
            app: app,
            appName: app,   // Yabai uses bundle ID as app name
            space: space,
            frame: frame,
            hasFocus: hasFocus,
            stackIndex: stackIndex,
            isMinimized: isMinimized,
            isHidden: isHidden,
            isVisible: isVisible,
            isFloating: false, // Yabai doesn't expose this in the standard query; would need per-window query
            isFullscreen: isNativeFullscreen
        )
    }
}

extension Display {
    func toWMDisplay() -> WMDisplay {
        WMDisplay(
            id: id,
            uuid: uuid,
            index: index,
            frame: frame,
            spaces: spaces,
            hasFocus: hasFocus
        )
    }
}

extension WMLayoutType {
    static func fromYabai(_ type: String) -> WMLayoutType {
        switch type {
        case "bsp": return .bsp
        case "float": return .float
        case "stack": return .stack
        default: return .unknown
        }
    }
}
