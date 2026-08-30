import CoreGraphics

/// Matches the shortcuts that belong to Aegis's app switcher.
///
/// The returned value indicates whether the shortcut requests reverse
/// navigation. Other modifier flags, such as Caps Lock and Fn, are ignored.
struct AppSwitcherShortcutMatcher {
    static let tabKeyCode: Int64 = 48

    static func reverseDirection(for keyCode: Int64, flags: CGEventFlags) -> Bool? {
        guard keyCode == tabKeyCode,
              flags.contains(.maskCommand),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskControl) else {
            return nil
        }

        return flags.contains(.maskShift)
    }
}
