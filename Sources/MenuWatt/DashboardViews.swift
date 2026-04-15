import AppKit
import SwiftUI
import MenuWattCore

struct MonitorPanelView: View {
    let battery: BatterySnapshot
    let system: SystemSnapshot
    let processes: ProcessEnergySnapshot
    let sprite: NSImage
    let visibleSections: Set<DashboardSection>

    var body: some View {
        let processPresentation = ProcessEnergySectionPresentation.make(from: processes)
        let showsProcesses = visibleSections.contains(.processes) && !processPresentation.isHidden

        VStack(spacing: 0) {
            HeroRow(battery: battery, sprite: sprite)

            if visibleSections.contains(.battery) {
                Divider().padding(.horizontal, 10)
                BatterySection(snapshot: battery)
            }

            if visibleSections.contains(.cpu) {
                Divider().padding(.horizontal, 10)
                CPUSection(snapshot: system.cpu)
            }

            if visibleSections.contains(.memory) {
                Divider().padding(.horizontal, 10)
                MemorySection(snapshot: system.memory)
            }

            if visibleSections.contains(.gpu) {
                Divider().padding(.horizontal, 10)
                GPUSection(snapshot: system.gpu)
            }

            if visibleSections.contains(.fan) {
                Divider().padding(.horizontal, 10)
                FanSection(snapshot: system.fan)
            }

            if visibleSections.contains(.network) {
                Divider().padding(.horizontal, 10)
                NetworkSection(snapshot: system.network)
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

            Text("\(battery.percentage)%")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .monospacedDigit()

            Text(presentation.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(presentation.themeColor)

            Spacer()

            if let powerText = battery.menuBarPowerText {
                Text(powerText)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct BatterySection: View {
    let snapshot: BatterySnapshot

    var body: some View {
        let presentation = BoochiPresentation.make(for: snapshot.state)

        VStack(alignment: .leading, spacing: 5) {
            NativeProgressBar(value: Double(snapshot.percentage) / 100, tint: presentation.themeColor)

            HStack(spacing: 0) {
                if let liveInput = snapshot.liveInputDetail {
                    InlineMetric(label: "Input", value: liveInput.valueText)
                }
                if let rate = snapshot.rateDetail {
                    InlineMetric(label: rate.kind.prefix, value: rate.valueText)
                }
                if let time = snapshot.timeDescription {
                    InlineMetric(label: "ETA", value: time)
                }
            }
            HStack(spacing: 0) {
                if let cycle = snapshot.cycleCount {
                    InlineMetric(label: "Cycle", value: "\(cycle)")
                }
                if let temp = snapshot.temperatureCelsius {
                    InlineMetric(label: "Temp", value: String(format: "%.1f°C", temp))
                }
                InlineMetric(label: "Source", value: snapshot.sourceDescription)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct CPUSection: View {
    let snapshot: CPUSnapshot

    var body: some View {
        let presentation = CPUSectionPresentation.make(from: snapshot)

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("CPU", systemImage: "cpu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(presentation.titleValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }

            if presentation.showsProgress {
                NativeProgressBar(value: snapshot.totalUsage / 100, tint: cpuTint(snapshot.totalUsage))
            }

            if presentation.showsMetrics {
                HStack(spacing: 0) {
                    InlineMetric(label: "Sys", value: String(format: "%.1f%%", snapshot.systemUsage))
                    InlineMetric(label: "User", value: String(format: "%.1f%%", snapshot.userUsage))
                    InlineMetric(label: "Idle", value: String(format: "%.1f%%", snapshot.idleUsage))
                }
            }

            if presentation.showsHistory {
                MiniGraphView(primarySamples: snapshot.history, secondarySamples: [])
                    .frame(height: 32)
            }

            if let unavailableMessage = presentation.unavailableMessage {
                UnavailableCaption(unavailableMessage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func cpuTint(_ usage: Double) -> Color {
        if usage > 80 { return .red }
        if usage > 50 { return .orange }
        return .blue
    }
}

struct MemorySection: View {
    let snapshot: MemorySnapshot

    var body: some View {
        let presentation = MemorySectionPresentation.make(from: snapshot)

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Memory", systemImage: "memorychip")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if presentation.showsPressureBadge {
                    PressureBadge(level: snapshot.pressureLevel)
                }
                Text(presentation.titleValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }

            if presentation.showsProgress {
                NativeProgressBar(
                    value: snapshot.usedPercent / 100,
                    tint: PressureLevelPresentation.themeColor(for: snapshot.pressureLevel)
                )
            }

            if presentation.showsMetrics {
                HStack(spacing: 0) {
                    InlineMetric(label: "Used", value: Formatters.bytes(snapshot.usedBytes))
                    InlineMetric(label: "App", value: Formatters.bytes(snapshot.appMemoryBytes))
                    InlineMetric(label: "Wired", value: Formatters.bytes(snapshot.wiredMemoryBytes))
                }
                HStack(spacing: 0) {
                    InlineMetric(label: "Compr", value: Formatters.bytes(snapshot.compressedBytes))
                    InlineMetric(label: "Cache", value: Formatters.bytes(snapshot.cachedFilesBytes))
                    InlineMetric(label: "Swap", value: Formatters.bytes(snapshot.swapUsedBytes))
                }
            }

            if let unavailableMessage = presentation.unavailableMessage {
                UnavailableCaption(unavailableMessage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct StorageSection: View {
    let snapshot: StorageSnapshot

    var body: some View {
        let presentation = StorageSectionPresentation.make(from: snapshot)

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Storage", systemImage: "internaldrive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let usageSummary = presentation.usageSummary {
                    Text(usageSummary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(presentation.titleValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }

            if presentation.showsProgress {
                NativeProgressBar(value: snapshot.usedPercent / 100, tint: storageTint(snapshot.usedPercent))
            }

            if let unavailableMessage = presentation.unavailableMessage {
                UnavailableCaption(unavailableMessage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func storageTint(_ percent: Double) -> Color {
        if percent > 90 { return .red }
        if percent > 75 { return .orange }
        return .cyan
    }
}

struct GPUSection: View {
    let snapshot: GPUSnapshot

    var body: some View {
        let presentation = GPUSectionPresentation.make(from: snapshot)

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("GPU", systemImage: "display")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(presentation.titleValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }

            if presentation.showsProgress {
                NativeProgressBar(value: snapshot.utilizationPercent / 100, tint: gpuTint(snapshot.utilizationPercent))
            }

            if presentation.showsHistory {
                MiniGraphView(primarySamples: snapshot.history, secondarySamples: [], primaryColor: .purple)
                    .frame(height: 32)
            }

            if let unavailableMessage = presentation.unavailableMessage {
                UnavailableCaption(unavailableMessage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func gpuTint(_ usage: Double) -> Color {
        if usage > 80 { return .red }
        if usage > 50 { return .orange }
        return .purple
    }
}

struct FanSection: View {
    let snapshot: FanSnapshot

    var body: some View {
        let presentation = FanSectionPresentation.make(from: snapshot)

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Fans", systemImage: "fan")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(presentation.titleValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }

            if !presentation.fans.isEmpty {
                HStack(spacing: 0) {
                    ForEach(presentation.fans) { fan in
                        InlineMetric(label: "Fan \(fan.index)", value: fanValueText(fan))
                    }
                }
            }

            if let unavailableMessage = presentation.unavailableMessage {
                UnavailableCaption(unavailableMessage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func fanValueText(_ fan: FanReading) -> String {
        if let percent = fan.percent {
            return String(format: "%.0f RPM (%.0f%%)", fan.rpm, percent)
        }
        return String(format: "%.0f RPM", fan.rpm)
    }
}

struct NetworkSection: View {
    let snapshot: NetworkSnapshot

    var body: some View {
        let presentation = NetworkSectionPresentation.make(from: snapshot)

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Network", systemImage: "network")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(presentation.titleValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }

            if presentation.unavailableMessage == nil {
                HStack(spacing: 0) {
                    InlineMetric(label: "↓", value: presentation.downloadText)
                    InlineMetric(label: "↑", value: presentation.uploadText)
                }
                if !presentation.totalsText.isEmpty {
                    Text(presentation.totalsText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            if presentation.showsHistory {
                MiniGraphView(primarySamples: snapshot.history, secondarySamples: [], primaryColor: .green)
                    .frame(height: 32)
            }

            if let unavailableMessage = presentation.unavailableMessage {
                UnavailableCaption(unavailableMessage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct ProcessEnergySectionView: View {
    let presentation: ProcessEnergySectionPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Top Energy", systemImage: "bolt")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let unavailableMessage = presentation.unavailableMessage {
                UnavailableCaption(unavailableMessage)
            }

            ForEach(presentation.entries) { entry in
                ProcessEnergyRow(entry: entry)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct ProcessEnergyRow: View {
    let entry: ProcessEnergyEntry

    @State private var isHovering = false
    private var runningApp: NSRunningApplication? {
        NSRunningApplication(processIdentifier: entry.pid)
    }

    var body: some View {
        let app = runningApp
        let displayName = app?.localizedName ?? entry.name

        Button {
            activate(app)
        } label: {
            HStack(spacing: 6) {
                ProcessIcon(icon: app?.icon)
                Text(displayName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: "%.1f", entry.energyImpact))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Click to activate • Right-click for more")
        .contextMenu {
            if let app {
                Button("Activate \(displayName)") { activate(app) }
                Button("Quit \(displayName)") { app.terminate() }
                Button("Force Quit \(displayName)") { app.forceTerminate() }
                Divider()
            }
            Button("Open Activity Monitor") { openActivityMonitor() }
            Button("Copy PID (\(entry.pid))") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(entry.pid), forType: .string)
            }
        }
    }

    private func activate(_ app: NSRunningApplication?) {
        if let app {
            app.activate(options: [.activateIgnoringOtherApps])
        } else {
            openActivityMonitor()
        }
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }
}

struct ProcessIcon: View {
    let icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 14, height: 14)
    }
}

struct UnavailableCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct InlineMetric: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NativeProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.quaternary)
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: clamped == 0 ? 0 : max(6, geo.size.width * clamped))
            }
        }
        .frame(height: 4)
    }
}

struct PressureBadge: View {
    let level: PressureLevel

    var body: some View {
        let themeColor = PressureLevelPresentation.themeColor(for: level)

        Text(level.title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(themeColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(themeColor.opacity(0.12))
            )
    }
}

struct MiniGraphView: View {
    let primarySamples: [Double]
    let secondarySamples: [Double]
    var primaryColor: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            let maxValue = max(primarySamples.max() ?? 0, secondarySamples.max() ?? 0, 1)

            ZStack {
                fillPath(for: primarySamples, in: geometry.size, maxValue: maxValue)
                    .fill(
                        LinearGradient(
                            colors: [primaryColor.opacity(0.2), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                graphPath(for: primarySamples, in: geometry.size, maxValue: maxValue)
                    .stroke(primaryColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

                if !secondarySamples.isEmpty {
                    graphPath(for: secondarySamples, in: geometry.size, maxValue: maxValue)
                        .stroke(Color.green.opacity(0.7), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                }
            }
        }
    }

    private func graphPath(for samples: [Double], in size: CGSize, maxValue: Double) -> Path {
        guard samples.count > 1 else { return Path() }
        let stepX = size.width / CGFloat(max(samples.count - 1, 1))
        return Path { path in
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * stepX
                let normalized = min(max(sample / maxValue, 0), 1)
                let y = size.height - CGFloat(normalized) * size.height
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func fillPath(for samples: [Double], in size: CGSize, maxValue: Double) -> Path {
        guard samples.count > 1 else { return Path() }
        let stepX = size.width / CGFloat(max(samples.count - 1, 1))
        return Path { path in
            path.move(to: CGPoint(x: 0, y: size.height))
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * stepX
                let normalized = min(max(sample / maxValue, 0), 1)
                let y = size.height - CGFloat(normalized) * size.height
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }
}
