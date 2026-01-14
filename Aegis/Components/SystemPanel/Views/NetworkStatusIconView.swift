import SwiftUI

struct NetworkStatusIconView: View {
    let status: NetworkStatus
    
    var body: some View {
        Image(systemName: iconName)
            .foregroundColor(iconColor)
    }
    
    private var iconName: String {
        switch status {
        case .wifi(let strength):
            if strength > 0.66 { return "wifi" }
            else if strength > 0.33 { return "wifi.exclamationmark" }
            else { return "wifi.slash" }
        case .ethernet: return "cable.connector"
        case .disconnected: return "wifi.slash"
        }
    }
    
    private var iconColor: Color {
        switch status {
        case .wifi(let strength): return strength > 0.33 ? .white : .red.opacity(0.8)
        case .ethernet: return .white
        case .disconnected: return .red.opacity(0.8)
        }
    }
}
