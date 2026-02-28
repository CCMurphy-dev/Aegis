import Foundation
import Combine
import AppKit

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published private(set) var isDarkMode: Bool = true

    private var cancellables = Set<AnyCancellable>()
    private var appearanceObserver: NSObjectProtocol?

    private init() {
        updateEffectiveAppearance()

        DistributedNotificationCenter.default().addObserver(
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
    }

    deinit {
        if let observer = appearanceObserver {
            NotificationCenter.default.removeObserver(observer)
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
        }

        if newIsDarkMode != isDarkMode {
            isDarkMode = newIsDarkMode
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
        }
    }

    private func isSystemInDarkMode() -> Bool {
        if let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return appearance == .darkAqua
        }
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}
