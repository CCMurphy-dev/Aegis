# Aegis File Documentation

A simple guide to what each file does.

---

## App/

**AppDelegate.swift**
Function: The main entry point of the app. Sets up all the components when Aegis launches and cleans up when it quits.
Author: Chris

---

## Core/Config/

**AegisConfig.swift**
Function: Stores all the settings for Aegis - sizes, colors, timings, and toggles. Settings are saved automatically so they persist between app restarts.
Author: Chris

---

## Core/Models/

**MusicInfo.swift**
Function: Holds information about the currently playing song - track name, artist, album, and artwork.
Author: Chris

**Space.swift**
Function: Represents a macOS workspace/space with its number, windows, and whether it's currently active.
Author: Chris

**WindowInfo.swift**
Function: Stores details about a window - its ID, title, app name, icon, and which space it belongs to.
Author: Chris

---

## Core/Services/

**EventRouter.swift**
Function: A messaging system that lets different parts of the app communicate without knowing about each other. Components can publish events and subscribe to events they care about.
Author: Chris

**MediaService.swift**
Function: Connects to Apple's private MediaRemote framework to get now-playing information from Music.app, Spotify, and other media apps.
Author: Chris

**StartupNotificationService.swift**
Function: Shows a macOS notification when Aegis starts, displaying the app version, Yabai version, and whether the integration is working.
Author: Chris

**SystemInfoService.swift**
Function: Gets system information like battery level, charging status, WiFi signal strength, and network name.
Author: Chris

**YabaiService.swift**
Function: Talks to the Yabai window manager. Queries spaces and windows, executes layout commands, and listens for changes via a named pipe.
Author: Chris

**YabaiSetupChecker.swift**
Function: Checks if Yabai integration is properly configured - whether Yabai is installed, signals are registered, and the notification script exists.
Author: Chris

---

## Components/MenuBar/Controllers/

**MenuBarController.swift**
Function: Creates and manages the menu bar window. Handles the right-click context menu with all the layout actions and settings.
Author: Chris

**MenuBarWindowController.swift**
Function: A custom window controller that creates a borderless, always-on-top window for the menu bar replacement.
Author: Chris

---

## Components/MenuBar/Coordinators/

**MenuBarCoordinator.swift**
Function: Orchestrates the menu bar components. Connects the view model to the Yabai service and handles drag-and-drop between spaces.
Author: Chris

---

## Components/MenuBar/ViewModels/

**MenuBarViewModel.swift**
Function: Holds the state for the menu bar view - the list of spaces, which space is active, and handles user interactions like clicking spaces.
Author: Chris

---

## Components/MenuBar/Views/

**MenuBarView.swift**
Function: The main SwiftUI view for the menu bar. Lays out the space indicators, system status, and handles animations.
Author: Chris

**SpaceView.swift**
Function: Draws a single space indicator - the numbered circle and the app icons for windows in that space.
Author: Chris

**WindowIconView.swift**
Function: Displays a single window's app icon with drag-and-drop support and hover effects.
Author: Chris

---

## Components/Notch/Controllers/

**NotchHUDController.swift**
Function: Manages the notch overlay window. Shows and hides the HUD for volume, brightness, and music changes.
Author: Chris

---

## Components/Notch/ViewModels/

**NotchHUDViewModel.swift**
Function: Holds state for the notch HUD - current volume/brightness levels, music info, and which mode is active.
Author: Chris

---

## Components/Notch/Views/

**BrightnessHUDView.swift**
Function: Displays a brightness indicator with a sun icon and animated progress bar when brightness changes.
Author: Chris

**MusicHUDView.swift**
Function: Shows now-playing information with album art, track details, and an animated audio visualizer.
Author: Chris

**NotchHUDView.swift**
Function: The container view for all HUD content. Handles the notch shape and transitions between different HUD modes.
Author: Chris

**VolumeHUDView.swift**
Function: Displays a volume indicator with a speaker icon and animated progress bar when volume changes.
Author: Chris

---

## Components/SettingsPanel/

**SettingsPanelView.swift**
Function: The settings interface with sliders, toggles, and color pickers for customizing every aspect of Aegis.
Author: Chris

**YabaiSetupPromptView.swift**
Function: A dialog that appears when Yabai integration isn't configured, offering to run the setup script.
Author: Chris

---

## Components/SystemStatus/Views/

**BatteryView.swift**
Function: Draws the battery icon with fill level and color based on charge percentage (green, yellow, orange, red).
Author: Chris

**ClockView.swift**
Function: Displays the current time and date in the menu bar with configurable format.
Author: Chris

**SystemStatusView.swift**
Function: Groups together the clock, WiFi, and battery indicators on the right side of the menu bar.
Author: Chris

**WiFiView.swift**
Function: Shows WiFi signal strength with a three-bar indicator icon.
Author: Chris

---

## Helpers/

**SpringAnimation.swift**
Function: Provides smooth spring-based animations using CVDisplayLink for 60fps interpolation.
Author: Chris

---

## Resources/

**mediaremote-adapter.pl**
Function: A Perl script that bridges Apple's private MediaRemote framework, allowing Aegis to get now-playing information.
Author: ungive (third-party)

---

## AegisYabaiIntegration/

**aegis-yabai-notify**
Function: A shell script that Yabai calls when events happen (window focus, space change). Writes events to a named pipe that Aegis reads.
Author: Chris

**setup-aegis-yabai.sh**
Function: The setup script that installs the notification script and registers Yabai signals for Aegis integration.
Author: Chris

---

## Root Files

**VERSION**
Function: Contains the current version number (0.2.3). Read by the build script to set the app version.
Author: Chris

**Info.plist**
Function: The app's configuration file with bundle identifier, version, permissions, and other macOS app settings.
Author: Chris
