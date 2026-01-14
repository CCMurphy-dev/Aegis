import Foundation
import Cocoa

/// Requests Automation permission for Yabai and Music.app.
/// Resolves Homebrew symlink so updates don't break it.
func requestAutomationPermission() {
    // Request permission for Yabai
    let symlinkPath = "/opt/homebrew/bin/yabai"
    let fileManager = FileManager.default

    let absolutePath = URL(fileURLWithPath: symlinkPath)
        .resolvingSymlinksInPath()
        .path

    let yabaiScript = """
    tell application "\(absolutePath)"
    end tell
    """

    if let script = NSAppleScript(source: yabaiScript) {
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error = error {
            print("❌ Yabai automation error: \(error)")
        } else {
            print("✅ Yabai automation allowed")
        }
    }

    // Request permission for Music.app
    let musicScript = """
    tell application "Music"
        get player state
    end tell
    """

    if let script = NSAppleScript(source: musicScript) {
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error = error {
            print("❌ Music automation error: \(error)")
            print("⚠️  Please grant Aegis permission to control Music.app:")
            print("    System Settings → Privacy & Security → Automation → Aegis → Enable Music")
        } else {
            print("✅ Music automation allowed")
        }
    }
}
