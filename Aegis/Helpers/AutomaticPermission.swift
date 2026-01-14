import Foundation
import Cocoa

/// Requests Automation permission for Yabai.
/// Resolves Homebrew symlink so updates don't break it.
///
/// Note: Music.app automation is no longer needed - MediaRemoteService uses
/// the MediaRemote private framework via mediaremote-adapter instead.
func requestAutomationPermission() {
    // Request permission for Yabai
    let symlinkPath = "/opt/homebrew/bin/yabai"

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
}
