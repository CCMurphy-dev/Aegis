import SwiftUI

struct BatteryStatusIconView: View {
    let level: Float
    let isCharging: Bool
    
    var body: some View {
        // Return empty view if fully charged and charging
        if isCharging && level >= 1.0 {
            EmptyView()
        } else {
            HStack(spacing: 2) {
                Image(systemName: icon)
                Text("\(Int(level * 100))%")
            }
        }
    }
    
    private var icon: String {
        if isCharging { return "bolt.fill" }
        else if level > 0.75 { return "battery.100" }
        else if level > 0.5 { return "battery.75" }
        else if level > 0.25 { return "battery.50" }
        else if level > 0.1 { return "battery.25" }
        else { return "battery.0" }
    }
}
