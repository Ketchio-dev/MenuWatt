import AppKit
import SwiftUI
import MenuWattCore

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
                .font(.system(size: 10, weight: .medium))
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
