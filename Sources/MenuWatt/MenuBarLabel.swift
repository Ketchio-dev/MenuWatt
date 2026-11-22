import AppKit
import SwiftUI
import MenuWattCore

/// The menu bar status item: sprite plus the selected indicator.
///
/// Extracted from BoochiApp.swift; indicator selection and fallback text
/// ("—" with a minimum width when a sensor is unavailable) unchanged.
struct MenuBarLabel: View {
    @ObservedObject var monitor: PowerMonitor
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        HStack(spacing: 4) {
            if preferences.showsSprite {
                Image(nsImage: monitor.currentFrame)
            }

            // Keep the recovery entry reachable when a sensor is unavailable
            // and the user has hidden the animated character.
            Text(indicatorText ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .frame(minWidth: indicatorText == nil ? 16 : nil)
                .accessibilityLabel(indicatorText ?? "\(preferences.menuBarIndicator.title) unavailable")
        }
        .help(BoochiPresentation.tooltip(for: monitor.snapshot))
        .onAppear {
            monitor.setRefreshInterval(preferences.refreshInterval.seconds)
        }
        .onChange(of: preferences.refreshInterval) { newValue in
            monitor.setRefreshInterval(newValue.seconds)
        }
    }

    private var indicatorText: String? {
        switch preferences.menuBarIndicator {
        case .power:
            return monitor.snapshot.menuBarPowerText
        case .battery:
            guard monitor.snapshot.state != .unavailable,
                  monitor.snapshot.state != .absent else { return nil }
            return "\(monitor.snapshot.percentage)%"
        case .cpu:
            guard monitor.systemSnapshot.cpu.isAvailable else { return nil }
            return String(format: "%.0f%%", monitor.systemSnapshot.cpu.totalUsage)
        case .temperature:
            guard let celsius = monitor.snapshot.temperatureCelsius else { return nil }
            return String(format: "%.0f°C", celsius)
        case .gpu:
            guard monitor.systemSnapshot.gpu.isAvailable else { return nil }
            return String(format: "%.0f%%", monitor.systemSnapshot.gpu.utilizationPercent)
        case .network:
            guard monitor.systemSnapshot.network.isAvailable else { return nil }
            let total = monitor.systemSnapshot.network.downloadBytesPerSecond
                + monitor.systemSnapshot.network.uploadBytesPerSecond
            return Formatters.bytesPerSecond(total)
        case .fan:
            guard let fan = monitor.systemSnapshot.fan.fans.first else { return nil }
            return String(format: "%.0f RPM", fan.rpm)
        }
    }
}
