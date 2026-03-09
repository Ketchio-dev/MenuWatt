public protocol MonitorSampling: Sendable {
    func sample() async -> SamplePayload
}

public struct SamplePayload: Sendable {
    public let battery: BatterySnapshot
    public let system: SystemSnapshot

    public init(battery: BatterySnapshot, system: SystemSnapshot) {
        self.battery = battery
        self.system = system
    }
}
