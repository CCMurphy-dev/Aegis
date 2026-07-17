//
//  WallpaperBlurService.swift
//  Aegis
//
//  Dynamically blurs the desktop wallpaper when windows are focused on the current space.
//  Captures the actual wallpaper image, applies CIGaussianBlur, and displays it
//  in a window just above the wallpaper layer.
//

import Cocoa
import Combine
import CoreImage
import ScreenCaptureKit

// MARK: - Blur Overlay Window

/// Borderless window that sits just above the wallpaper and shows a blurred copy of it
class BlurOverlayWindow: NSWindow {
    private let imageView: NSImageView

    init(screen: NSScreen) {
        imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        sharingType = .none
        alphaValue = 0

        contentView = imageView
        setFrame(screen.frame, display: false)
        orderFrontRegardless()
    }

    func setBlurredImage(_ image: NSImage?) {
        imageView.image = image
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Wallpaper Blur Service

class WallpaperBlurService {
    private let eventRouter: EventRouter
    private let config = AegisConfig.shared
    private var cancellables = Set<AnyCancellable>()

    private var blurWindows: [NSScreen: BlurOverlayWindow] = [:]
    private var blurredImages: [NSScreen: NSImage] = [:]
    private var blurredScreens: Set<NSScreen> = []
    private var debounceTimer: DispatchWorkItem?
    private var pollTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    /// Blur radius for the gaussian blur (in points)
    private let blurRadius: CGFloat = 40

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter
        setupConfigObservation()

        if config.enableWallpaperBlur {
            start()
        }
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    private func start() {
        createBlurWindows()
        generateBlurredWallpapers()
        setupWorkspaceObservers()
        startPollTimer()
        evaluateFocusState()
    }

    private func stop() {
        stopPollTimer()
        removeWorkspaceObservers()
        destroyBlurWindows()
        blurredImages.removeAll()
        blurredScreens.removeAll()
    }

    // MARK: - Config Observation

    private func setupConfigObservation() {
        config.$enableWallpaperBlur
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.start()
                } else {
                    self?.stop()
                }
            }
            .store(in: &cancellables)

        config.$wallpaperBlurIntensity
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.blurredScreens.isEmpty else { return }
                self.updateBlurAlpha(animate: false)
            }
            .store(in: &cancellables)
    }

    // MARK: - Wallpaper Capture & Blur

    private func generateBlurredWallpapers() {
        for screen in NSScreen.screens {
            captureAndBlurWallpaper(for: screen)
        }
    }

    private func captureAndBlurWallpaper(for screen: NSScreen) {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                // Find the SCDisplay matching this NSScreen by display ID
                let screenDisplayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                guard let scDisplay = content.displays.first(where: { display in
                    display.displayID == screenDisplayID
                }) else {
                    print("WallpaperBlur: No matching SCDisplay for screen \(screenDisplayID ?? 0)")
                    return
                }

                // Exclude normal app windows (layer 0) AND our own windows (any layer) — keep only wallpaper
                let myPID = ProcessInfo.processInfo.processIdentifier
                let appWindows = content.windows.filter { $0.windowLayer == 0 || $0.owningApplication?.processID == myPID }
                let filter = SCContentFilter(display: scDisplay, excludingWindows: appWindows)

                let config = SCStreamConfiguration()
                config.width = Int(screen.frame.width * screen.backingScaleFactor)
                config.height = Int(screen.frame.height * screen.backingScaleFactor)
                config.captureResolution = .best
                config.showsCursor = false

                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )

                // Apply gaussian blur on a background queue
                let blurRadius = self.blurRadius
                let screenSize = screen.frame.size
                let blurredImage: NSImage? = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let ciImage = CIImage(cgImage: cgImage)

                        // Clamp edges to prevent blur vignette at image borders
                        guard let clampFilter = CIFilter(name: "CIAffineClamp") else {
                            continuation.resume(returning: nil)
                            return
                        }
                        clampFilter.setValue(ciImage, forKey: kCIInputImageKey)
                        clampFilter.setValue(CGAffineTransform.identity, forKey: kCIInputTransformKey)
                        guard let clampedInput = clampFilter.outputImage else {
                            continuation.resume(returning: nil)
                            return
                        }

                        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
                            continuation.resume(returning: nil)
                            return
                        }
                        blurFilter.setValue(clampedInput, forKey: kCIInputImageKey)
                        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)
                        guard let outputImage = blurFilter.outputImage else {
                            continuation.resume(returning: nil)
                            return
                        }

                        let clampedImage = outputImage.cropped(to: ciImage.extent)
                        let context = CIContext(options: [.useSoftwareRenderer: false])
                        guard let blurredCG = context.createCGImage(clampedImage, from: ciImage.extent) else {
                            continuation.resume(returning: nil)
                            return
                        }

                        let nsImage = NSImage(cgImage: blurredCG, size: screenSize)
                        continuation.resume(returning: nsImage)
                    }
                }

                // Apply on main thread
                if let blurredImage {
                    await MainActor.run {
                        self.blurredImages[screen] = blurredImage
                        self.blurWindows[screen]?.setBlurredImage(blurredImage)
                    }
                }
            } catch {
                print("WallpaperBlur: Failed to capture desktop: \(error)")
            }
        }
    }

    // MARK: - Blur Windows

    private func createBlurWindows() {
        destroyBlurWindows()
        for screen in NSScreen.screens {
            let window = BlurOverlayWindow(screen: screen)
            blurWindows[screen] = window
        }
    }

    private func destroyBlurWindows() {
        for (_, window) in blurWindows {
            window.orderOut(nil)
        }
        blurWindows.removeAll()
    }

    /// Rebuild blur windows when displays change
    func handleDisplayChange() {
        guard config.enableWallpaperBlur else { return }
        blurredScreens.removeAll()
        createBlurWindows()
        generateBlurredWallpapers()
        evaluateFocusState()
    }

    // MARK: - Workspace Observers

    private func setupWorkspaceObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default

        // App activation -- primary trigger
        let activateObs = workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.debouncedEvaluate()
        }

        // App deactivation
        let deactivateObs = workspace.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.debouncedEvaluate()
        }

        // Space changed
        let spaceObs = workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.debouncedEvaluate()
        }

        // Display configuration changed
        let screenObs = nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleDisplayChange()
        }

        workspaceObservers = [activateObs, deactivateObs, spaceObs, screenObs]
    }

    private func removeWorkspaceObservers() {
        for obs in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            NotificationCenter.default.removeObserver(obs)
        }
        workspaceObservers.removeAll()

    }

    // MARK: - Focus Detection

    private func debouncedEvaluate() {
        debounceTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.evaluateFocusState()
        }
        debounceTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func evaluateFocusState() {
        let screensWithWindows = screensWithVisibleWindows()

        for (screen, window) in blurWindows {
            let shouldBlur = screensWithWindows.contains(screen)
            let wasBlurred = blurredScreens.contains(screen)

            guard shouldBlur != wasBlurred else { continue }

            if shouldBlur {
                blurredScreens.insert(screen)
            } else {
                blurredScreens.remove(screen)
            }
            setBlurAlpha(for: window, show: shouldBlur, animate: true)
        }
    }

    private func screensWithVisibleWindows() -> Set<NSScreen> {
        let myPID = ProcessInfo.processInfo.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var result = Set<NSScreen>()

        for windowInfo in windowList {
            guard let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0 else { continue }

            guard let pid = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                  pid != myPID else { continue }

            guard let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat,
                  width >= 50, height >= 50 else { continue }

            // Exclude Dock and system UI
            if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String {
                if ownerName == "Dock" || ownerName == "WindowManager" || ownerName == "Window Server" {
                    continue
                }
            }

            // Determine which screen this window is on (by center point)
            let windowCenter = CGPoint(x: x + width / 2, y: y + height / 2)
            if let screen = screenContaining(point: windowCenter) {
                result.insert(screen)
            }
        }

        return result
    }

    /// Find which NSScreen contains a given point (in CGWindow/global coordinates — top-left origin)
    private func screenContaining(point: CGPoint) -> NSScreen? {
        // CGWindowList uses top-left origin; NSScreen.frame uses bottom-left.
        // Convert by flipping Y relative to the primary screen height.
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let flippedY = primaryHeight - point.y

        for screen in NSScreen.screens {
            if screen.frame.contains(CGPoint(x: point.x, y: flippedY)) {
                return screen
            }
        }
        return nil
    }

    // MARK: - Animation

    private func updateBlurAlpha(animate: Bool) {
        let targetAlpha = CGFloat(config.wallpaperBlurIntensity)
        for screen in blurredScreens {
            if let window = blurWindows[screen] {
                setBlurAlpha(for: window, show: true, animate: animate)
            }
        }
    }

    private func setBlurAlpha(for window: BlurOverlayWindow, show: Bool, animate: Bool) {
        let targetAlpha: CGFloat = show ? CGFloat(config.wallpaperBlurIntensity) : 0

        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = show ? 0.3 : 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = targetAlpha
            }
        } else {
            window.alphaValue = targetAlpha
        }
    }

    // MARK: - Poll Timer (safety net)

    private func startPollTimer() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.evaluateFocusState()
        }
    }

    private func stopPollTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
