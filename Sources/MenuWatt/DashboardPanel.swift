import AppKit
import SwiftUI
import MenuWattCore

struct MonitorPanelView: View {
    let battery: BatterySnapshot
    let system: SystemSnapshot
    let processes: ProcessEnergySnapshot
    let sprite: NSImage
    let visibleSections: Set<DashboardSection>
    let showsGraphs: Bool

    init(
        battery: BatterySnapshot,
        system: SystemSnapshot,
        processes: ProcessEnergySnapshot,
        sprite: NSImage,
        visibleSections: Set<DashboardSection>,
        showsGraphs: Bool = true
    ) {
        self.battery = battery
        self.system = system
        self.processes = processes
        self.sprite = sprite
        self.visibleSections = visibleSections
        self.showsGraphs = showsGraphs
    }

    var body: some View {
        let processPresentation = ProcessEnergySectionPresentation.make(from: processes)
        let showsProcesses = visibleSections.contains(.processes) && !processPresentation.isHidden

        VStack(spacing: 0) {
            HeroRow(battery: battery, sprite: sprite)

            if visibleSections.contains(.battery) && battery.state != .absent && battery.state != .unavailable {
                Divider().padding(.horizontal, 10)
                BatterySection(snapshot: battery)
            }

            if visibleSections.contains(.cpu) {
                Divider().padding(.horizontal, 10)
                CPUSection(snapshot: system.cpu, showsGraphs: showsGraphs)
            }

            if visibleSections.contains(.memory) {
                Divider().padding(.horizontal, 10)
                MemorySection(snapshot: system.memory)
            }

            if visibleSections.contains(.gpu) {
                Divider().padding(.horizontal, 10)
                GPUSection(snapshot: system.gpu, showsGraphs: showsGraphs)
            }

            if visibleSections.contains(.fan) {
                Divider().padding(.horizontal, 10)
                FanSection(snapshot: system.fan)
            }

            if visibleSections.contains(.network) {
                Divider().padding(.horizontal, 10)
                NetworkSection(snapshot: system.network, showsGraphs: showsGraphs)
            }

            if visibleSections.contains(.storage) {
                Divider().padding(.horizontal, 10)
                StorageSection(snapshot: system.storage)
            }

            if showsProcesses {
                Divider().padding(.horizontal, 10)
                ProcessEnergySectionView(presentation: processPresentation)
            }
        }
    }
}

struct HeroRow: View {
    let battery: BatterySnapshot
    let sprite: NSImage

    var body: some View {
        let presentation = BoochiPresentation.make(for: battery.state)

        HStack(spacing: 10) {
            Image(nsImage: sprite)
                .resizable()
                .interpolation(.none)
                .frame(width: 28, height: 28)

            if battery.state == .unavailable {
                Text(presentation.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            } else if battery.state == .absent {
                // Desktop Mac: no battery percentage — headline the live power draw.
                if let powerText = battery.menuBarPowerText {
                    Text(powerText)
                        .font(.system(size: 20, weight: .semibold))
                        .monospacedDigit()
                    Text(presentation.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(presentation.themeColor)
                } else {
                    Text("MenuWatt")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                Text("\(battery.percentage)%")
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()

                Text(presentation.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(presentation.themeColor)

                Spacer()

                if let powerText = battery.menuBarPowerText {
                    Text(powerText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
