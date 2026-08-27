import Foundation

/// Decides what a context-button click or scroll should do.
/// Kept independent of AppKit so the interaction contract is easy to test.
enum ContextButtonInteraction: Equatable {
    case selectAction
    case requestMenu
    case ignore
}

enum ContextButtonInteractionPolicy {
    static func primaryClick(menuOnly: Bool) -> ContextButtonInteraction {
        menuOnly ? .requestMenu : .selectAction
    }

    static func rightClick() -> ContextButtonInteraction {
        .requestMenu
    }

    static func scroll(menuOnly: Bool) -> ContextButtonInteraction {
        menuOnly ? .ignore : .selectAction
    }
}
