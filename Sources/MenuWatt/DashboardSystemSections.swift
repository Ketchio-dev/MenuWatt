import AppKit
import SwiftUI
import MenuWattCore

struct GPUSection: View {
    let snapshot: GPUSnapshot
    let showsGraphs: Bool

    init(snapshot: GPUSnapshot, showsGraphs: Bool = true) {
        self.snapshot = snapshot
        self.showsGraphs = showsGraphs
    }

    var body: some View {
        let presentation = GPUSectionPresentation.make(from: snapshot)

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("GPU", systemImage: "display")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(presentation.titleValue)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }

            if presentation.showsProgress {
                NativeProgressBar(value: snapshot.utilizationPercent / 100, tint: gpuTint(snapshot.utilizationPercent))
            }

            if showsGraphs && presentation.showsHistory {
                MiniGraphView(primarySamples: snapshot.history, secondarySamples: [], primaryColor: .purple)
                    .frame(height: 32)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("GPU history")
                    .accessibilityAddTraits(.isImage)
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

    @State private var showsDetails = false

    var body: some View {
        let presentation = FanSectionPresentation.make(from: snapshot)

        VStack(alignment: .leading, spacing: 5) {
            DashboardDetailsHeader(title: "Fan details", isEnabled: !presentation.fans.isEmpty,
                                   isExpanded: $showsDetails) {
                HStack {
                    Label("Fans", systemImage: "fan")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(presentation.titleValue).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
            }

            if !presentation.fans.isEmpty && showsDetails {
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
    let showsGraphs: Bool

    @State private var showsDetails = false

    init(snapshot: NetworkSnapshot, showsGraphs: Bool = true) {
        self.snapshot = snapshot
        self.showsGraphs = showsGraphs
    }

    var body: some View {
        let presentation = NetworkSectionPresentation.make(from: snapshot)

        VStack(alignment: .leading, spacing: 5) {
            DashboardDetailsHeader(title: "Network totals", isEnabled: !presentation.totalsText.isEmpty,
                                   isExpanded: $showsDetails) {
                HStack {
                    Label("Network", systemImage: "network")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(presentation.titleValue).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
            }

            if presentation.unavailableMessage == nil {
                HStack(spacing: 0) {
                    InlineMetric(label: "↓", value: presentation.downloadText)
                    InlineMetric(label: "↑", value: presentation.uploadText)
                }
            }

            if showsGraphs && presentation.showsHistory {
                MiniGraphView(primarySamples: snapshot.history, secondarySamples: [], primaryColor: .green)
                    .frame(height: 32)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Network history")
                    .accessibilityAddTraits(.isImage)
            }

            if !presentation.totalsText.isEmpty && showsDetails {
                Text(presentation.totalsText).font(.system(size: 10))
                    .foregroundStyle(.secondary).monospacedDigit()
            }

            if let unavailableMessage = presentation.unavailableMessage {
                UnavailableCaption(unavailableMessage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct DashboardDetailsHeader<Header: View>: View {
    let title: String
    let isEnabled: Bool
    @Binding var isExpanded: Bool
    @ViewBuilder let header: Header

    var body: some View {
        if isEnabled {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 5) {
                    header
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 18)
                }
                .frame(minHeight: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .help(isExpanded ? "Hide details" : "Show details")
        } else {
            header
        }
    }
}
