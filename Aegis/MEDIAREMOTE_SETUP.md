# MediaRemote Setup Guide

This guide explains how to configure the MediaRemote adapter in your Xcode project to enable system-wide "Now Playing" functionality.

## Overview

The MediaRemoteService replaces the old MusicService and provides access to system-wide now playing information from **ALL media sources**:
- Music.app
- Spotify
- Safari / Firefox / Chrome
- YouTube
- Any app that publishes media info

## Required Files

The following files have been added to your project:

### 1. Service Implementation
- `Core/Services/MediaRemoteService.swift` - Main service that monitors system-wide media

### 2. Adapter Files (in Resources/)
- `Resources/mediaremote-adapter.pl` - Perl script that interfaces with MediaRemote framework
- `Resources/MediaRemoteAdapter.framework/` - Framework that wraps private MediaRemote API

## Xcode Project Configuration

### Step 1: Add Resources to Xcode

1. Open `Aegis.xcodeproj` in Xcode
2. Right-click on the `Aegis` group in the project navigator
3. Select **Add Files to "Aegis"...**
4. Navigate to `/Users/chris/Dev/Aegis/Aegis/Resources/`
5. Select both:
   - `mediaremote-adapter.pl`
   - `MediaRemoteAdapter.framework`
6. **IMPORTANT**: In the dialog, ensure:
   - ☑️ "Copy items if needed" is **UNCHECKED** (files are already in place)
   - ☑️ "Add to targets" has **Aegis** selected
   - Create groups: **Resources** (for the .pl file)

### Step 2: Configure Build Phases

#### Add mediaremote-adapter.pl to Copy Bundle Resources

1. Select the **Aegis** project in the navigator
2. Select the **Aegis** target
3. Go to the **Build Phases** tab
4. Expand **Copy Bundle Resources**
5. Click the **+** button
6. Add `mediaremote-adapter.pl`

#### Add MediaRemoteAdapter.framework to Embed Frameworks

1. Still in **Build Phases**, find or create **Embed Frameworks** phase
   - If it doesn't exist, click **+** → **New Copy Files Phase**
   - Set Destination to **Frameworks**
   - Name it "Embed Frameworks"
2. Click the **+** button under Embed Frameworks
3. Add `MediaRemoteAdapter.framework`
4. **IMPORTANT**: Set "Code Sign On Copy" to **Sign** (not "Do Not Sign")

**Note**: Do NOT add MediaRemoteAdapter.framework to "Link Binary With Libraries" - we're only embedding it, not linking it.

### Step 3: Verify File Locations in Build Settings

1. Go to **Build Settings** tab
2. Search for "Framework Search Paths"
3. Ensure it includes: `$(PROJECT_DIR)/Aegis/Resources`
4. Search for "PRODUCT_NAME"
5. Verify it's set to `$(TARGET_NAME)`

### Step 4: Add MediaRemoteService.swift to Target

1. Select `Core/Services/MediaRemoteService.swift` in the navigator
2. In the File Inspector (right panel), ensure the **Target Membership** checkbox for **Aegis** is checked

## Code Changes (Already Applied)

The following code changes have already been made:

### AppDelegate.swift
```swift
// Changed from:
var musicService: MusicService?

// To:
var musicService: MediaRemoteService?

// And in setupServices():
musicService = MediaRemoteService(eventRouter: eventRouter!)
```

### NotchHUDController.swift
```swift
// Changed from:
private let musicService: MusicService

// To:
private let musicService: MediaRemoteService
```

## Testing

### 1. Build the Project

1. Clean build folder: **Product** → **Clean Build Folder** (Cmd+Shift+K)
2. Build: **Product** → **Build** (Cmd+B)
3. Check for errors related to missing files or resources

### 2. Run and Test

1. Run the app: **Product** → **Run** (Cmd+R)
2. Check the console for startup messages:
   ```
   🎵 MediaRemoteService: Starting media monitoring
   🎵 MediaRemoteService: Stream started successfully
   ```

3. Test with different media sources:
   - **Music.app**: Play a song
   - **Spotify**: Play a song (if installed)
   - **Safari**: Play a YouTube video
   - **Firefox/Chrome**: Play media on any site

4. Verify the music HUD appears in the notch showing:
   - Album art (left side)
   - Visualizer (right side, normal state)
   - Track title + artist (right side, for 5 seconds after track change)

### 3. Troubleshooting

#### Error: "Unable to locate mediaremote-adapter.pl"
- Check that `mediaremote-adapter.pl` is in **Copy Bundle Resources** build phase
- Verify the file exists at `/Users/chris/Dev/Aegis/Aegis/Resources/mediaremote-adapter.pl`

#### Error: "Unable to locate MediaRemoteAdapter.framework"
- Check that framework is in **Embed Frameworks** phase (NOT "Link Binary")
- Verify it's set to "Code Sign On Copy"
- Check framework exists at `/Users/chris/Dev/Aegis/Aegis/Resources/MediaRemoteAdapter.framework`

#### No media detected
- Open Console.app and filter for "MediaRemoteService"
- Check if stream started successfully
- Try playing media in Music.app first (most reliable)
- Ensure macOS accessibility permissions are granted

## How It Works

1. **MediaRemoteService** spawns a Perl process running `mediaremote-adapter.pl`
2. The Perl script loads `MediaRemoteAdapter.framework`
3. The framework wraps macOS's private MediaRemote.framework
4. Perl has the necessary entitlements to access MediaRemote (bypasses macOS 15.4+ restrictions)
5. The adapter streams JSON updates with media info
6. MediaRemoteService parses JSON and publishes to EventRouter
7. NotchHUDController receives updates and displays in the notch

## Distribution Considerations

### Direct Distribution
✅ **Safe**: You can distribute this app directly (via DMG, ZIP, GitHub releases)
- The adapter approach is a workaround, not a hack
- No system modifications required
- No SIP disable needed

### Mac App Store
⚠️ **May Be Rejected**: The MediaRemote framework is private API
- Apple may reject during review
- Consider distributing outside the App Store
- Or use TestFlight for beta distribution

## References

- [mediaremote-adapter GitHub](https://github.com/ungive/mediaremote-adapter)
- [MediaRemote.framework Documentation](https://theapplewiki.com/wiki/Dev:MediaRemote.framework)
- [macOS 15.4 MediaRemote Changes](https://github.com/feedback-assistant/reports/issues/637)

## Support

If you encounter issues:
1. Check Console.app logs filtered by "MediaRemoteService"
2. Verify both adapter files are properly embedded in the app bundle
3. Test with Music.app first (most reliable source)
