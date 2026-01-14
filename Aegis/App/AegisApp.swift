import SwiftUI
import Combine

@main
struct AegisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var config = AegisConfig.shared
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}


// Simple settings view for now
struct SettingsView: View {
    @StateObject private var config = AegisConfig.shared
    
    var body: some View {
        Form {
            Section("Menu Bar Layout") {
                HStack {
                    Text("Height:")
                    Slider(value: $config.menuBarHeight, in: 24...48, step: 2)
                    Text("\(Int(config.menuBarHeight))px")
                        .frame(width: 50)
                }
                
                HStack {
                    Text("Edge Padding:")
                    Slider(value: $config.menuBarEdgePadding, in: 0...32, step: 2)
                    Text("\(Int(config.menuBarEdgePadding))px")
                        .frame(width: 50)
                }
                
                HStack {
                    Text("Space Spacing:")
                    Slider(value: $config.spaceIndicatorSpacing, in: 2...16, step: 2)
                    Text("\(Int(config.spaceIndicatorSpacing))px")
                        .frame(width: 50)
                }
                
                HStack {
                    Text("Icon Spacing:")
                    Slider(value: $config.systemIconSpacing, in: 4...24, step: 2)
                    Text("\(Int(config.systemIconSpacing))px")
                        .frame(width: 50)
                }
            }
            
            Section("Features") {
                Toggle("Show workspace indicators", isOn: .constant(true))
                Toggle("Enable notch HUD", isOn: .constant(true))
                Toggle("Show system status", isOn: .constant(true))
            }
            
            Section("Yabai Integration") {
                HStack {
                    Text("Status:")
                    Text("Connected")
                        .foregroundColor(.green)
                }
            }
            
            Divider()
            
            HStack {
                Button("Reset to Defaults") {
                    config.resetToDefaults()
                }
                
                Spacer()
                
                Button("Save") {
                    config.savePreferences()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 450)
    }
}
