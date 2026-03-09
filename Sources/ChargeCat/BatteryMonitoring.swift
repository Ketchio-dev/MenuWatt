import AppKit
import IOKit
import IOKit.ps
import SwiftUI

enum BatteryReader {
    static func read() -> BatterySnapshot {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [AnyObject]
        let metrics = SmartBatteryReader.read()

        guard let firstSource = sources.first,
              let description = IOPSGetPowerSourceDescription(info, firstSource)?.takeUnretainedValue() as? [String: Any] else {
            return .unavailable
        }

        let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int ?? 0
        let maxCapacity = max(description[kIOPSMaxCapacityKey as String] as? Int ?? 100, 1)
        let percentage = Int((Double(currentCapacity) / Double(maxCapacity) * 100.0).rounded())
        let isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
        let isCharged = description[kIOPSIsChargedKey as String] as? Bool ?? false
        let sourceState = description[kIOPSPowerSourceStateKey as String] as? String ?? kIOPSBatteryPowerValue
        let name = description[kIOPSNameKey as String] as? String ?? "Battery"

        let state: BatteryState
        if isCharged {
            state = .full
        } else if isCharging {
            state = .charging
        } else if sourceState == kIOPSACPowerValue {
            state = .pluggedIn
        } else {
            state = .onBattery
        }

        let timeEstimate: BatteryTimeEstimate?
        switch state {
        case .charging:
            timeEstimate = Self.makeTimeEstimate(
                minutes: description[kIOPSTimeToFullChargeKey as String] as? Int,
                context: .untilFull
            )
        case .onBattery:
            timeEstimate = Self.makeTimeEstimate(
                minutes: description[kIOPSTimeToEmptyKey as String] as? Int,
                context: .remaining
            )
        default:
            timeEstimate = nil
        }

        let rateDetail = Self.makeRateDetail(state: state, metrics: metrics)
        let liveInputDetail = Self.makeLiveInputDetail(state: state, metrics: metrics)

        return BatterySnapshot(
            name: name,
            percentage: percentage,
            state: state,
            sourceDescription: sourceState == kIOPSACPowerValue ? "Power Adapter" : "Battery",
            timeEstimate: timeEstimate,
            rateDetail: rateDetail,
            liveInputDetail: liveInputDetail,
            batteryWatts: metrics?.batteryWatts,
            adapterWatts: metrics?.adapterWatts,
            systemInputWatts: metrics?.systemInputWatts,
            systemLoadWatts: metrics?.systemLoadWatts,
            cycleCount: metrics?.cycleCount,
            temperatureCelsius: metrics?.temperatureCelsius,
            updatedAt: .now
        )
    }

    private static func makeTimeEstimate(minutes: Int?, context: BatteryTimeEstimate.Context) -> BatteryTimeEstimate? {
        guard let minutes, minutes > 0 else { return nil }
        return BatteryTimeEstimate(context: context, minutes: minutes)
    }

    private static func makeRateDetail(state: BatteryState, metrics: SmartBatteryMetrics?) -> BatteryPowerDetail? {
        guard let metrics else { return nil }

        switch state {
        case .charging:
            if let batteryWatts = metrics.batteryWatts, batteryWatts > 0.05 {
                return BatteryPowerDetail(kind: .charging, watts: batteryWatts)
            }
            if let adapterWatts = metrics.adapterWatts, adapterWatts > 0 {
                return BatteryPowerDetail(kind: .adapter, watts: adapterWatts)
            }
        case .onBattery, .pluggedIn, .full:
            if let detail = usageDetail(from: metrics) {
                return detail
            }
            if state != .onBattery, let adapterWatts = metrics.adapterWatts, adapterWatts > 0 {
                return BatteryPowerDetail(kind: .adapter, watts: adapterWatts)
            }
        case .unavailable:
            return nil
        }

        return nil
    }

    private static func usageDetail(from metrics: SmartBatteryMetrics) -> BatteryPowerDetail? {
        if let systemLoadWatts = metrics.systemLoadWatts, systemLoadWatts > 0.05 {
            return BatteryPowerDetail(kind: .usage, watts: systemLoadWatts)
        }
        if let batteryWatts = metrics.batteryWatts, batteryWatts > 0.05 {
            return BatteryPowerDetail(kind: .usage, watts: batteryWatts)
        }
        return nil
    }

    private static func makeLiveInputDetail(state: BatteryState, metrics: SmartBatteryMetrics?) -> BatteryPowerDetail? {
        guard let metrics else { return nil }

        if let systemInputWatts = metrics.systemInputWatts, systemInputWatts > 0.05 {
            switch state {
            case .charging:
                return BatteryPowerDetail(kind: .liveInput, watts: systemInputWatts)
            case .pluggedIn, .full, .onBattery, .unavailable:
                break
            }
        }

        return nil
    }
}

struct BatteryTimeEstimate: Sendable {
    enum Context: Sendable {
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

    let context: Context
    let minutes: Int

    var description: String {
        "\(context.prefix) \(valueText)"
    }

    var valueText: String {
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

struct BatteryPowerDetail: Sendable {
    enum Kind: Sendable {
        case charging
        case usage
        case adapter
        case liveInput

        var prefix: String {
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

    let kind: Kind
    let watts: Double

    var description: String {
        "\(kind.prefix) \(valueText)"
    }

    var valueText: String {
        if kind.usesFractionalWatts {
            return String(format: "%.1f W", watts)
        }

        return String(format: "%.0f W", watts)
    }
}

struct BatterySnapshot: Sendable {
    let name: String
    let percentage: Int
    let state: BatteryState
    let sourceDescription: String
    let timeEstimate: BatteryTimeEstimate?
    let rateDetail: BatteryPowerDetail?
    let liveInputDetail: BatteryPowerDetail?
    let batteryWatts: Double?
    let adapterWatts: Double?
    let systemInputWatts: Double?
    let systemLoadWatts: Double?
    let cycleCount: Int?
    let temperatureCelsius: Double?
    let updatedAt: Date

    static let unavailable = BatterySnapshot(
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

    var timeDescription: String? {
        timeEstimate?.description
    }

    var rateDescription: String? {
        rateDetail?.description
    }

    var liveInputDescription: String? {
        liveInputDetail?.description
    }

    var headline: String {
        "\(percentage)% \(state.title)"
    }

    var adapterDescription: String? {
        guard let adapterWatts, adapterWatts > 0 else { return nil }
        if let systemInputWatts, systemInputWatts > 0.05 {
            return String(format: "Input %.1f W / Adapter %.0f W", systemInputWatts, adapterWatts)
        }
        return String(format: "Adapter %.0f W", adapterWatts)
    }

    var menuBarPowerText: String? {
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

    var tooltip: String {
        let extraLines = [timeDescription, rateDescription, liveInputDescription, adapterDescription].compactMap { $0 }
        if extraLines.isEmpty {
            return headline
        }

        return ([headline] + extraLines).joined(separator: "\n")
    }
}

struct SmartBatteryMetrics: Sendable {
    let batteryWatts: Double?
    let adapterWatts: Double?
    let systemInputWatts: Double?
    let systemLoadWatts: Double?
    let cycleCount: Int?
    let temperatureCelsius: Double?
}

enum SmartBatteryReader {
    static func read() -> SmartBatteryMetrics? {
        guard let entry = matchingService(named: "AppleSmartBattery") else {
            return nil
        }
        defer { IOObjectRelease(entry) }

        guard let properties = properties(for: entry) else {
            return nil
        }

        let amperage = numericValue(for: ["InstantAmperage", "Amperage"], in: properties)
        let voltage = numericValue(for: ["Voltage"], in: properties)
        let batteryWatts = watts(amperageMilliAmps: amperage, voltageMilliVolts: voltage)

        let adapterDetails = properties["AdapterDetails"] as? [String: Any]
        let adapterWatts = number(from: adapterDetails?["Watts"])?.doubleValue

        let telemetry = properties["PowerTelemetryData"] as? [String: Any]
        let systemInputMilliWatts = number(from: telemetry?["SystemPowerIn"])?.doubleValue
        let systemInputWatts = systemInputMilliWatts.map { $0 / 1000.0 }
        let systemLoadMilliWatts = number(from: telemetry?["SystemLoad"])?.doubleValue
        let systemLoadWatts = systemLoadMilliWatts.map { $0 / 1000.0 }
        let cycleCount = number(from: properties["CycleCount"])?.intValue
        let temperatureRaw = number(from: properties["Temperature"])?.doubleValue
        let temperatureCelsius = temperatureRaw.map { $0 / 100.0 }

        return SmartBatteryMetrics(
            batteryWatts: batteryWatts,
            adapterWatts: adapterWatts,
            systemInputWatts: systemInputWatts,
            systemLoadWatts: systemLoadWatts,
            cycleCount: cycleCount,
            temperatureCelsius: temperatureCelsius
        )
    }

    private static func matchingService(named serviceName: String) -> io_service_t? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceName))
        return service == 0 ? nil : service
    }

    private static func properties(for entry: io_registry_entry_t) -> [String: Any]? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(entry, &unmanagedProperties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let unmanagedProperties else {
            return nil
        }

        return unmanagedProperties.takeRetainedValue() as? [String: Any]
    }

    private static func numericValue(for keys: [String], in dictionary: [String: Any]) -> Double? {
        for key in keys {
            if let value = number(from: dictionary[key])?.doubleValue {
                return value
            }
        }
        return nil
    }

    private static func number(from value: Any?) -> NSNumber? {
        if let number = value as? NSNumber {
            return number
        }
        if let string = value as? String, let doubleValue = Double(string) {
            return NSNumber(value: doubleValue)
        }
        return nil
    }

    private static func watts(amperageMilliAmps: Double?, voltageMilliVolts: Double?) -> Double? {
        guard let amperageMilliAmps, let voltageMilliVolts else { return nil }
        let watts = abs(amperageMilliAmps * voltageMilliVolts) / 1_000_000.0
        return watts > 0.01 ? watts : nil
    }
}

enum BatteryState: Equatable, Sendable {
    case charging
    case pluggedIn
    case onBattery
    case full
    case unavailable

    var title: String {
        switch self {
        case .charging:
            return "Charging"
        case .pluggedIn:
            return "On Adapter"
        case .onBattery:
            return "On Battery"
        case .full:
            return "Fully Charged"
        case .unavailable:
            return "Unavailable"
        }
    }

    var themeColor: Color {
        switch self {
        case .charging:
            return .yellow
        case .pluggedIn:
            return .blue
        case .onBattery:
            return .orange
        case .full:
            return .green
        case .unavailable:
            return .gray
        }
    }

    var animationInterval: TimeInterval {
        switch self {
        case .charging:
            return 0.14
        case .pluggedIn:
            return 0.45
        case .onBattery:
            return 0.60
        case .full:
            return 0.80
        case .unavailable:
            return 1.0
        }
    }

    var frames: [SpriteFrame] {
        switch self {
        case .charging:
            return [.run1, .run2, .run3, .run4]
        case .pluggedIn:
            return [.run1, .run2, .run3, .run4] // Use run animation instead of idle
        case .onBattery:
            return [.run1, .run2, .run3, .run4] // Use run animation instead of sleep
        case .full:
            return [.run1, .run2, .run3, .run4] // Use run animation instead of full
        case .unavailable:
            return [.sleep1]
        }
    }
}
