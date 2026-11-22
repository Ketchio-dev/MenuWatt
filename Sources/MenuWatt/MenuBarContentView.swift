import AppKit
import SwiftUI
import MenuWattCore

private enum MenuWattLayout {
    static let menuPanelWidth: CGFloat = 340
}

/// The monitoring popover: live metrics plus Settings/Quit footer.
///
/// Extracted from BoochiApp.swift. Only live monitoring belongs in the
/// popover; cleanup controls live in Settings.
struct MenuBarContentView: View {
    @ObservedObject var monitor: PowerMonitor
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var cleanup: MenuBarCleanupController

    var body: some View {
        MenuBarDashboardView(
            battery: monitor.snapshot,
            system: monitor.systemSnapshot,
            processes: monitor.processSnapshot,
            sprite: monitor.currentFrame,
            visibleSections: preferences.visibleDashboardSections,
            showsGraphs: preferences.showsGraphs,
            onOpenSettings: {
                MenuBarPanelDismisser.dismiss()
                AppDelegate.sharedSettingsPanel?.show()
            },
            onQuit: {
                cleanup.stop()
                monitor.stop()
                NSApp.terminate(nil)
            }
        )
    }
}

/// Only live monitoring belongs in the popover; cleanup controls live in Settings.
struct MenuBarDashboardView: View {
    let battery: BatterySnapshot
    let system: SystemSnapshot
    let processes: ProcessEnergySnapshot
    let sprite: NSImage
    let visibleSections: Set<DashboardSection>
    let showsGraphs: Bool
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    private var maximumMetricsHeight: CGFloat {
        min(600, max(200, (NSScreen.main?.visibleFrame.height ?? 800) - 120))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                MonitorPanelView(battery: battery, system: system, processes: processes,
                                 sprite: sprite, visibleSections: visibleSections,
                                 showsGraphs: showsGraphs)
            }
            .frame(maxHeight: maximumMetricsHeight)
            .fixedSize(horizontal: false, vertical: true)

            Divider()
            MenuBarActionsView(onOpenSettings: onOpenSettings, onQuit: onQuit)
        }
        .frame(width: MenuWattLayout.menuPanelWidth)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MenuBarActionsView: View {
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpenSettings) {
                HStack(spacing: 3) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                    Text("Settings")
                }
                .padding(.horizontal, 6)
                .frame(minHeight: 24)
                .contentShape(Rectangle())
            }

            Spacer()

            Button(action: onQuit) {
                Text("Quit MenuWatt")
                    .padding(.horizontal, 6)
                    .frame(minHeight: 24)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

@MainActor
enum MenuBarPanelDismisser {
    static func dismiss() {
        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            if className.contains("MenuBarExtra") || className.contains("NSStatusBarWindow") {
                window.orderOut(nil)
            }
        }
    }
}
