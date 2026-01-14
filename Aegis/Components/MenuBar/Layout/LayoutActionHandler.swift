import Foundation

// MARK: - Layout Action Handler Protocol
// Protocol defining all layout and space management actions

protocol LayoutActionHandler {
    // Space actions
    func focusSpace(_ index: Int)
    func createSpace()
    func destroySpace(_ index: Int)

    // Window actions
    func focusWindow(_ windowId: Int)
    func moveWindowToSpace(_ windowId: Int, spaceIndex: Int, insertBeforeWindowId: Int?, shouldStack: Bool)
    func getWindowSpace(_ windowId: Int) -> Int?

    // Layout actions
    func rotateLayout(_ degrees: Int)
    func flipLayout(axis: String)
    func balanceLayout()
    func toggleLayout()
    func toggleStackAllWindowsInCurrentSpace()
}
