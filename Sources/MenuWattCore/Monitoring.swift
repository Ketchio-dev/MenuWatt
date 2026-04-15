public protocol MonitorSampling: Sendable {
    func sample() async -> SamplePayload
}

public struct SamplePayload: Sendable {
    public let battery: BatterySnapshot
    public let system: SystemSnapshot
    public let processes: ProcessEnergySnapshot

    public init(
        battery: BatterySnapshot,
        system: SystemSnapshot,
        processes: ProcessEnergySnapshot = .unavailable
    ) {
        self.battery = battery
        self.system = system
        self.processes = processes
    }
}
