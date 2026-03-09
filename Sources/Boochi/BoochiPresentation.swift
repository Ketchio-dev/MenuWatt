import SwiftUI
import BoochiCore

struct BoochiPresentation {
    let title: String
    let themeColor: Color
    let animationFrames: [SpriteFrame]
    let baseInterval: TimeInterval
    let fallbackFrame: SpriteFrame

    static let runningFrames: [SpriteFrame] = [.run1, .run2, .run3, .run4]

    static func make(for state: BatteryState) -> BoochiPresentation {
        switch state {
        case .charging:
            return BoochiPresentation(
                title: "Charging",
                themeColor: .yellow,
                animationFrames: runningFrames,
                baseInterval: 0.14,
                fallbackFrame: .run1
            )
        case .pluggedIn:
            return BoochiPresentation(
                title: "On Adapter",
                themeColor: .blue,
                animationFrames: runningFrames,
                baseInterval: 0.45,
                fallbackFrame: .run1
            )
        case .onBattery:
            return BoochiPresentation(
                title: "On Battery",
                themeColor: .orange,
                animationFrames: runningFrames,
                baseInterval: 0.60,
                fallbackFrame: .run1
            )
        case .full:
            return BoochiPresentation(
                title: "Fully Charged",
                themeColor: .green,
                animationFrames: runningFrames,
                baseInterval: 0.80,
                fallbackFrame: .run1
            )
        case .unavailable:
            return BoochiPresentation(
                title: "Unavailable",
                themeColor: .gray,
                animationFrames: runningFrames,
                baseInterval: 1.0,
                fallbackFrame: .run1
            )
        }
    }

    static func tooltip(for snapshot: BatterySnapshot) -> String {
        let title = make(for: snapshot.state).title
        let headline = "\(snapshot.percentage)% \(title)"
        let extraLines = [
            snapshot.timeDescription,
            snapshot.rateDescription,
            snapshot.liveInputDescription,
            snapshot.adapterDescription
        ].compactMap { $0 }

        if extraLines.isEmpty {
            return headline
        }

        return ([headline] + extraLines).joined(separator: "\n")
    }
}

enum BoochiAnimationPolicy {
    static func interval(
        for state: BatteryState,
        cpuUsage: Double,
        minimumInterval: TimeInterval
    ) -> TimeInterval {
        let presentation = BoochiPresentation.make(for: state)
        let normalizedCPU = max(0, min(100.0, cpuUsage))
        let speedMultiplier = 1.0 + (normalizedCPU / 100.0) * 9.0
        return max(minimumInterval, presentation.baseInterval / speedMultiplier)
    }
}

enum PressureLevelPresentation {
    static func themeColor(for level: PressureLevel) -> Color {
        switch level {
        case .normal:
            return .green
        case .warn:
            return .yellow
        case .critical:
            return .red
        }
    }
}
