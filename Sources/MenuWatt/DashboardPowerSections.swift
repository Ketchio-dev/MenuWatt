import AppKit
import SwiftUI
import MenuWattCore

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
                if let temp = snapshot.temperatureCelsius {
                    InlineMetric(label: "Temp", value: String(format: "%.1f°C", temp))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct CPUSection: View {
    let snapshot: CPUSnapshot
    let showsGraphs: Bool

    @State private var showsDetails = false

    init(snapshot: CPUSnapshot, showsGraphs: Bool = true) {
        self.snapshot = snapshot
        self.showsGraphs = showsGraphs
    }

    var body: some View {
        let presentation = CPUSectionPresentation.make(from: snapshot)

        VStack(alignment: .leading, spacing: 5) {
            DashboardDetailsHeader(title: "CPU details", isEnabled: presentation.showsMetrics,
                                   isExpanded: $showsDetails) {
                HStack {
                    Label("CPU", systemImage: "cpu")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(presentation.titleValue).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
            }

            if presentation.showsProgress {
                NativeProgressBar(value: snapshot.totalUsage / 100, tint: cpuTint(snapshot.totalUsage))
            }

            if showsGraphs && presentation.showsHistory {
                MiniGraphView(primarySamples: snapshot.history, secondarySamples: [])
                    .frame(height: 32)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("CPU history")
                    .accessibilityAddTraits(.isImage)
            }

            if presentation.showsMetrics && showsDetails {
                HStack(spacing: 0) {
                    InlineMetric(label: "Sys", value: String(format: "%.1f%%", snapshot.systemUsage))
                    InlineMetric(label: "User", value: String(format: "%.1f%%", snapshot.userUsage))
                    InlineMetric(label: "Idle", value: String(format: "%.1f%%", snapshot.idleUsage))
                }
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

    @State private var showsDetails = false

    var body: some View {
        let presentation = MemorySectionPresentation.make(from: snapshot)

        VStack(alignment: .leading, spacing: 5) {
            DashboardDetailsHeader(title: "Memory details", isEnabled: presentation.showsMetrics,
                                   isExpanded: $showsDetails) {
                HStack {
                    Label("Memory", systemImage: "memorychip")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if presentation.showsPressureBadge { PressureBadge(level: snapshot.pressureLevel) }
                    Text(presentation.titleValue).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
            }

            if presentation.showsProgress {
                NativeProgressBar(
                    value: snapshot.usedPercent / 100,
                    tint: PressureLevelPresentation.themeColor(for: snapshot.pressureLevel)
                )
            }

            if presentation.showsMetrics && showsDetails {
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
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(presentation.titleValue)
                    .font(.system(size: 12, weight: .semibold))
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
