import Foundation
import Combine
import AppKit

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published private(set) var isDarkMode: Bool = true
    @Published private(set) var themeRevision: Int = 0

    private var cancellables = Set<AnyCancellable>()
    private var appearanceObserver: NSObjectProtocol?
    private var distributedObserver: NSObjectProtocol?

    private init() {
        // Set initial state directly — don't post notification during init
        // to avoid reentrancy deadlock (observers access ThemeManager.shared
        // which is still being constructed)
        switch AegisConfig.shared.appTheme {
        case .dark: isDarkMode = true
        case .light: isDarkMode = false
        case .system: isDarkMode = isSystemInDarkMode()
        case .custom: isDarkMode = true
        case .liquidGlass: isDarkMode = isSystemInDarkMode()
        }

        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateEffectiveAppearance()
        }

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateEffectiveAppearance()
        }

        AegisConfig.shared.$appTheme
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateEffectiveAppearance()
            }
            .store(in: &cancellables)

        // Post theme change when custom colors change (even if isDarkMode doesn't)
        // Debounce custom color changes to avoid CPU spikes from color picker drag
        let colorDebounce: RunLoop.SchedulerTimeType.Stride = .milliseconds(100)

        AegisConfig.shared.$customBackgroundColor
            .dropFirst()
            .debounce(for: colorDebounce, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.themeRevision += 1
                NotificationCenter.default.post(name: .themeDidChange, object: nil)
            }
            .store(in: &cancellables)

        AegisConfig.shared.$customTextColor
            .dropFirst()
            .debounce(for: colorDebounce, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.themeRevision += 1
                NotificationCenter.default.post(name: .themeDidChange, object: nil)
            }
            .store(in: &cancellables)

        AegisConfig.shared.$customBorderColor
            .dropFirst()
            .debounce(for: colorDebounce, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.themeRevision += 1
                NotificationCenter.default.post(name: .themeDidChange, object: nil)
            }
            .store(in: &cancellables)
    }

    deinit {
        if let observer = appearanceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = distributedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    private func updateEffectiveAppearance() {
        let newIsDarkMode: Bool

        switch AegisConfig.shared.appTheme {
        case .dark:
            newIsDarkMode = true
        case .light:
            newIsDarkMode = false
        case .system:
            newIsDarkMode = isSystemInDarkMode()
        case .custom:
            newIsDarkMode = true  // Custom uses dark as base
        case .liquidGlass:
            newIsDarkMode = isSystemInDarkMode()
        }

        if newIsDarkMode != isDarkMode {
            isDarkMode = newIsDarkMode
        }
        themeRevision += 1
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }

    private func isSystemInDarkMode() -> Bool {
        if let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return appearance == .darkAqua
        }
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}
