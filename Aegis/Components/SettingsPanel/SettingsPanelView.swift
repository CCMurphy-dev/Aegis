import SwiftUI

/// Main Settings Panel for configuring Aegis
/// Organized into 4 tabs: General, Menu Bar, Notch HUD, Appearance
struct SettingsPanelView: View {
    @ObservedObject var config = AegisConfig.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case menuBar = "Menu Bar"
        case notchHUD = "Notch HUD"
        case appearance = "Appearance"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .menuBar: return "menubar.rectangle"
            case .notchHUD: return "rectangle.topthird.inset.filled"
            case .appearance: return "paintbrush"
            }
        }
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                Divider()
                    .background(Color.white.opacity(0.2))

                // Tab Bar
                tabBar

                Divider()
                    .background(Color.white.opacity(0.15))

                // Content Area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case .general:
                            SettingsGeneralTab()
                        case .menuBar:
                            SettingsMenuBarTab()
                        case .notchHUD:
                            SettingsNotchHUDTab()
                        case .appearance:
                            SettingsAppearanceTab()
                        }
                    }
                    .padding()
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                // Footer with actions
                footer
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Aegis Settings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text("Changes are saved automatically")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.6))
            }

            Spacer()

            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .medium))

                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(selectedTab == tab ? .white : Color.white.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        selectedTab == tab
                            ? Color.white.opacity(0.1)
                            : Color.clear
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                if tab != SettingsTab.allCases.last {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            SettingsActionButton(
                title: "Reset to Defaults",
                icon: "arrow.counterclockwise",
                destructive: true
            ) {
                config.resetToDefaults()
            }

            Spacer()

            Button("Done") {
                config.savePreferences()
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(SettingsPrimaryButtonStyle())
        }
        .padding()
        .background(Color.black.opacity(0.3))
    }
}

// MARK: - Settings Subsection

struct SettingsSubsection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.7))
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(.leading, 4)
        }
    }
}

// MARK: - Button Styles

struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(configuration.isPressed ? 0.15 : 0.1))
            .cornerRadius(6)
    }
}

struct SettingsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(configuration.isPressed ? 0.7 : 1.0))
            .cornerRadius(8)
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsPanelView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsPanelView()
            .frame(width: 500, height: 700)
    }
}
#endif
