import Foundation
import IOKit
import IOKit.ps
import MenuWattCore

public struct LiveBatterySnapshotReader {
    struct PowerSourceSnapshot: Sendable {
        let currentCapacity: Int
        let maxCapacity: Int
        let isCharging: Bool
        let isCharged: Bool
        let sourceState: String
        let name: String
        let timeToFullCharge: Int?
        let timeToEmpty: Int?
    }

    struct Dependencies: Sendable {
        let readPowerSourceSnapshot: @Sendable () -> PowerSourceSnapshot?
        let readMetrics: @Sendable () -> SmartBatteryMetrics?
        let now: @Sendable () -> Date

        static let live = Dependencies(
            readPowerSourceSnapshot: LiveBatteryPowerSourceReader.read,
            readMetrics: SmartBatteryMetricsReader().read,
            now: Date.init
        )
    }

    private let dependencies: Dependencies

    public init() {
        self.dependencies = .live
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    public func read() -> BatterySnapshot {
        let metrics = dependencies.readMetrics()

        guard let source = dependencies.readPowerSourceSnapshot() else {
            return .unavailable
        }

        let maxCapacity = max(source.maxCapacity, 1)
        let percentage = Int((Double(source.currentCapacity) / Double(maxCapacity) * 100.0).rounded())

        let state: BatteryState
        if source.isCharged {
            state = .full
        } else if source.isCharging {
            state = .charging
        } else if source.sourceState == kIOPSACPowerValue {
            state = .pluggedIn
        } else {
            state = .onBattery
        }

        let timeEstimate: BatteryTimeEstimate?
        switch state {
        case .charging:
            timeEstimate = makeTimeEstimate(
                minutes: source.timeToFullCharge,
                context: .untilFull
            )
        case .onBattery:
            timeEstimate = makeTimeEstimate(
                minutes: source.timeToEmpty,
                context: .remaining
            )
        case .pluggedIn, .full, .unavailable:
            timeEstimate = nil
        }

        return BatterySnapshot(
            name: source.name,
            percentage: percentage,
            state: state,
            sourceDescription: source.sourceState == kIOPSACPowerValue ? "Power Adapter" : "Battery",
            timeEstimate: timeEstimate,
            rateDetail: makeRateDetail(state: state, metrics: metrics),
            liveInputDetail: makeLiveInputDetail(state: state, metrics: metrics),
            batteryWatts: metrics?.batteryWatts,
            adapterWatts: metrics?.adapterWatts,
            systemInputWatts: metrics?.systemInputWatts,
            systemLoadWatts: metrics?.systemLoadWatts,
            cycleCount: metrics?.cycleCount,
            temperatureCelsius: metrics?.temperatureCelsius,
            updatedAt: dependencies.now()
        )
    }

    private func makeTimeEstimate(minutes: Int?, context: BatteryTimeEstimate.Context) -> BatteryTimeEstimate? {
        guard let minutes, minutes > 0 else { return nil }
        return BatteryTimeEstimate(context: context, minutes: minutes)
    }

    private func makeRateDetail(state: BatteryState, metrics: SmartBatteryMetrics?) -> BatteryPowerDetail? {
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

    private func makeLiveInputDetail(state: BatteryState, metrics: SmartBatteryMetrics?) -> BatteryPowerDetail? {
        guard let metrics,
              let systemInputWatts = metrics.systemInputWatts,
              systemInputWatts > 0.05,
              state == .charging else {
            return nil
        }

        return BatteryPowerDetail(kind: .liveInput, watts: systemInputWatts)
    }

    private func usageDetail(from metrics: SmartBatteryMetrics) -> BatteryPowerDetail? {
        if let systemLoadWatts = metrics.systemLoadWatts, systemLoadWatts > 0.05 {
            return BatteryPowerDetail(kind: .usage, watts: systemLoadWatts)
        }
        if let batteryWatts = metrics.batteryWatts, batteryWatts > 0.05 {
            return BatteryPowerDetail(kind: .usage, watts: batteryWatts)
        }
        return nil
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

private enum LiveBatteryPowerSourceReader {
    static func read() -> LiveBatterySnapshotReader.PowerSourceSnapshot? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [AnyObject]

        guard let firstSource = sources.first,
              let description = IOPSGetPowerSourceDescription(info, firstSource)?.takeUnretainedValue() as? [String: Any] else {
            return nil
        }

        return LiveBatterySnapshotReader.PowerSourceSnapshot(
            currentCapacity: description[kIOPSCurrentCapacityKey as String] as? Int ?? 0,
            maxCapacity: description[kIOPSMaxCapacityKey as String] as? Int ?? 100,
            isCharging: description[kIOPSIsChargingKey as String] as? Bool ?? false,
            isCharged: description[kIOPSIsChargedKey as String] as? Bool ?? false,
            sourceState: description[kIOPSPowerSourceStateKey as String] as? String ?? kIOPSBatteryPowerValue,
            name: description[kIOPSNameKey as String] as? String ?? "Battery",
            timeToFullCharge: description[kIOPSTimeToFullChargeKey as String] as? Int,
            timeToEmpty: description[kIOPSTimeToEmptyKey as String] as? Int
        )
    }
}

struct SmartBatteryMetricsReader {
    func read() -> SmartBatteryMetrics? {
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

    private func matchingService(named serviceName: String) -> io_service_t? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceName))
        return service == 0 ? nil : service
    }

    private func properties(for entry: io_registry_entry_t) -> [String: Any]? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(entry, &unmanagedProperties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let unmanagedProperties else {
            return nil
        }

        return unmanagedProperties.takeRetainedValue() as? [String: Any]
    }

    private func numericValue(for keys: [String], in dictionary: [String: Any]) -> Double? {
        for key in keys {
            if let value = number(from: dictionary[key])?.doubleValue {
                return value
            }
        }
        return nil
    }

    private func number(from value: Any?) -> NSNumber? {
        if let number = value as? NSNumber {
            return number
        }
        if let string = value as? String, let doubleValue = Double(string) {
            return NSNumber(value: doubleValue)
        }
        return nil
    }

    private func watts(amperageMilliAmps: Double?, voltageMilliVolts: Double?) -> Double? {
        guard let amperageMilliAmps, let voltageMilliVolts else { return nil }
        let watts = abs(amperageMilliAmps * voltageMilliVolts) / 1_000_000.0
        return watts > 0.01 ? watts : nil
    }
}
