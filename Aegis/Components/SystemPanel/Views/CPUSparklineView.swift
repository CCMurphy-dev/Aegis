import SwiftUI

struct CPUSparklineView: View {
    @ObservedObject private var monitor = CPURAMMonitor.shared
    @ObservedObject private var config = AegisConfig.shared

    private var color: Color { thresholdColor(monitor.cpuUsage) }
    private var pct: Int { Int(monitor.cpuUsage * 100) }

    var body: some View {
        switch config.monitorDisplayStyle {
        case .graph:
            HStack(spacing: 2) {
                SparklineGraph(values: monitor.cpuHistory, color: color)
                    .frame(width: 30, height: 12)
                Text("\(pct)%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(color)
            }
        case .percentage:
            HStack(spacing: 1) {
                Image(systemName: "cpu")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(color)
                Text("\(pct)%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(color)
            }
        case .pill:
            MonitorPillView(value: monitor.cpuUsage, label: "\(pct)%", color: color)
        }
    }

    private func thresholdColor(_ value: Float) -> Color {
        if value > 0.8 { return .red }
        if value > 0.5 { return .yellow }
        return .green
    }
}

struct RAMSparklineView: View {
    @ObservedObject private var monitor = CPURAMMonitor.shared
    @ObservedObject private var config = AegisConfig.shared

    private var color: Color { thresholdColor(monitor.ramUsage) }
    private var label: String { String(format: "%.1fG", monitor.ramUsedGB) }

    var body: some View {
        switch config.monitorDisplayStyle {
        case .graph:
            HStack(spacing: 2) {
                SparklineGraph(values: monitor.ramHistory, color: color)
                    .frame(width: 30, height: 12)
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(color)
            }
        case .percentage:
            HStack(spacing: 1) {
                Image(systemName: "memorychip")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(color)
            }
        case .pill:
            MonitorPillView(value: monitor.ramUsage, label: label, color: color)
        }
    }

    private func thresholdColor(_ value: Float) -> Color {
        if value > 0.8 { return .red }
        if value > 0.5 { return .yellow }
        return .green
    }
}

struct MonitorPillView: View {
    let value: Float
    let label: String
    let color: Color

    private let pillWidth: CGFloat = 34
    private let pillHeight: CGFloat = 14

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.black.opacity(0.5))
                .frame(width: pillWidth, height: pillHeight)
            Capsule()
                .fill(color)
                .frame(width: max(pillHeight, pillWidth * CGFloat(value)), height: pillHeight)
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 0.5, x: 0, y: 0.5)
                .frame(width: pillWidth, height: pillHeight)
        }
        .compositingGroup()
    }
}

struct SparklineGraph: View {
    let values: [Float]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2 {
                Path { path in
                    let w = geo.size.width
                    let h = geo.size.height
                    let step = w / CGFloat(values.count - 1)

                    for (i, value) in values.enumerated() {
                        let x = CGFloat(i) * step
                        let y = h - CGFloat(min(max(value, 0), 1)) * h
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, lineWidth: 1)
            }
        }
    }
}
