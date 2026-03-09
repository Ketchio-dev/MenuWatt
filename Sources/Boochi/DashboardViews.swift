import AppKit
import SwiftUI
import MenuWattCore

struct MonitorPanelView: View {
    let battery: BatterySnapshot
    let system: SystemSnapshot
    let sprite: NSImage

    var body: some View {
        VStack(spacing: 0) {
            HeroRow(battery: battery, sprite: sprite)

            Divider().padding(.horizontal, 10)

            BatterySection(snapshot: battery)

            Divider().padding(.horizontal, 10)

            CPUSection(snapshot: system.cpu)

            Divider().padding(.horizontal, 10)

            MemorySection(snapshot: system.memory)

            Divider().padding(.horizontal, 10)

            StorageSection(snapshot: system.storage)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("CPU", systemImage: "cpu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.titleValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }

            NativeProgressBar(value: snapshot.totalUsage / 100, tint: cpuTint(snapshot.totalUsage))

            HStack(spacing: 0) {
                InlineMetric(label: "Sys", value: String(format: "%.1f%%", snapshot.systemUsage))
                InlineMetric(label: "User", value: String(format: "%.1f%%", snapshot.userUsage))
                InlineMetric(label: "Idle", value: String(format: "%.1f%%", snapshot.idleUsage))
            }

            if !snapshot.history.isEmpty {
                MiniGraphView(primarySamples: snapshot.history, secondarySamples: [])
                    .frame(height: 32)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Memory", systemImage: "memorychip")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PressureBadge(level: snapshot.pressureLevel)
                Text(snapshot.titleValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }

            NativeProgressBar(
                value: snapshot.usedPercent / 100,
                tint: PressureLevelPresentation.themeColor(for: snapshot.pressureLevel)
            )

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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct StorageSection: View {
    let snapshot: StorageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Storage", systemImage: "internaldrive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Formatters.bytes(snapshot.usedBytes)) / \(Formatters.bytes(snapshot.totalBytes))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(snapshot.titleValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }

            NativeProgressBar(value: snapshot.usedPercent / 100, tint: storageTint(snapshot.usedPercent))
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
