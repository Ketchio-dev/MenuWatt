import Foundation

public enum BatteryState: Equatable, Sendable {
    case charging
    case pluggedIn
    case onBattery
    case full
    case unavailable
}

public struct BatteryTimeEstimate: Sendable {
    public enum Context: Sendable {
        case untilFull
        case remaining

        var prefix: String {
            switch self {
            case .untilFull:
                return "Full in"
            case .remaining:
                return "Remaining"
            }
        }
    }

    public let context: Context
    public let minutes: Int

    public init(context: Context, minutes: Int) {
        self.context = context
        self.minutes = minutes
    }

    public var description: String {
        "\(context.prefix) \(valueText)"
    }

    public var valueText: String {
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours == 0 {
            return "\(remainder)m"
        }

        if remainder == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(remainder)m"
    }
}

public struct BatteryPowerDetail: Sendable {
    public enum Kind: Sendable {
        case charging
        case usage
        case adapter
        case liveInput

        public var prefix: String {
            switch self {
            case .charging:
                return "Charging"
            case .usage:
                return "Usage"
            case .adapter:
                return "Adapter"
            case .liveInput:
                return "Live input"
            }
        }

        var usesFractionalWatts: Bool {
            switch self {
            case .adapter:
                return false
            case .charging, .usage, .liveInput:
                return true
            }
        }
    }

    public let kind: Kind
    public let watts: Double

    public init(kind: Kind, watts: Double) {
        self.kind = kind
        self.watts = watts
    }

    public var description: String {
        "\(kind.prefix) \(valueText)"
    }

    public var valueText: String {
        if kind.usesFractionalWatts {
            return String(format: "%.1f W", watts)
        }

        return String(format: "%.0f W", watts)
    }
}

public struct BatterySnapshot: Sendable {
    public let name: String
    public let percentage: Int
    public let state: BatteryState
    public let sourceDescription: String
    public let timeEstimate: BatteryTimeEstimate?
    public let rateDetail: BatteryPowerDetail?
    public let liveInputDetail: BatteryPowerDetail?
    public let batteryWatts: Double?
    public let adapterWatts: Double?
    public let systemInputWatts: Double?
    public let systemLoadWatts: Double?
    public let cycleCount: Int?
    public let temperatureCelsius: Double?
    public let updatedAt: Date

    public init(
        name: String,
        percentage: Int,
        state: BatteryState,
        sourceDescription: String,
        timeEstimate: BatteryTimeEstimate?,
        rateDetail: BatteryPowerDetail?,
        liveInputDetail: BatteryPowerDetail?,
        batteryWatts: Double?,
        adapterWatts: Double?,
        systemInputWatts: Double?,
        systemLoadWatts: Double?,
        cycleCount: Int?,
        temperatureCelsius: Double?,
        updatedAt: Date
    ) {
        self.name = name
        self.percentage = percentage
        self.state = state
        self.sourceDescription = sourceDescription
        self.timeEstimate = timeEstimate
        self.rateDetail = rateDetail
        self.liveInputDetail = liveInputDetail
        self.batteryWatts = batteryWatts
        self.adapterWatts = adapterWatts
        self.systemInputWatts = systemInputWatts
        self.systemLoadWatts = systemLoadWatts
        self.cycleCount = cycleCount
        self.temperatureCelsius = temperatureCelsius
        self.updatedAt = updatedAt
    }

    public static let unavailable = BatterySnapshot(
        name: "Battery",
        percentage: 0,
        state: .unavailable,
        sourceDescription: "Unknown",
        timeEstimate: nil,
        rateDetail: nil,
        liveInputDetail: nil,
        batteryWatts: nil,
        adapterWatts: nil,
        systemInputWatts: nil,
        systemLoadWatts: nil,
        cycleCount: nil,
        temperatureCelsius: nil,
        updatedAt: .now
    )

    public var timeDescription: String? {
        timeEstimate?.description
    }

    public var rateDescription: String? {
        rateDetail?.description
    }

    public var liveInputDescription: String? {
        liveInputDetail?.description
    }

    public var adapterDescription: String? {
        guard let adapterWatts, adapterWatts > 0 else { return nil }
        if let systemInputWatts, systemInputWatts > 0.05 {
            return String(format: "Input %.1f W / Adapter %.0f W", systemInputWatts, adapterWatts)
        }
        return String(format: "Adapter %.0f W", adapterWatts)
    }

    public var menuBarPowerText: String? {
        switch state {
        case .onBattery:
            if let systemLoadWatts, systemLoadWatts > 0.05 {
                return String(format: "%.1fW", systemLoadWatts)
            }
            if let batteryWatts, batteryWatts > 0.05 {
                return String(format: "%.1fW", batteryWatts)
            }
        case .charging:
            if let systemInputWatts, systemInputWatts > 0.05 {
                return String(format: "%.1fW", systemInputWatts)
            }
            if let batteryWatts, batteryWatts > 0.05 {
                return String(format: "%.1fW", batteryWatts)
            }
            if let adapterWatts, adapterWatts > 0 {
                return String(format: "%.0fW", adapterWatts)
            }
        case .pluggedIn, .full:
            if let systemLoadWatts, systemLoadWatts > 0.05 {
                return String(format: "%.1fW", systemLoadWatts)
            }
            if let systemInputWatts, systemInputWatts > 0.05 {
                return String(format: "%.1fW", systemInputWatts)
            }
            if let adapterWatts, adapterWatts > 0 {
                return String(format: "%.0fW", adapterWatts)
            }
        case .unavailable:
            break
        }

        return nil
    }
}
