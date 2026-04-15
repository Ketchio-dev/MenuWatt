import MenuWattCore

public actor LiveMonitorSampler: MonitorSampling {
    private let batteryReader: LiveBatterySnapshotReader
    private let systemReader: LiveSystemSnapshotReader
    private let processReader: LiveProcessEnergyReader

    public init(
        batteryReader: LiveBatterySnapshotReader = LiveBatterySnapshotReader(),
        systemReader: LiveSystemSnapshotReader = LiveSystemSnapshotReader(),
        processReader: LiveProcessEnergyReader = LiveProcessEnergyReader()
    ) {
        self.batteryReader = batteryReader
        self.systemReader = systemReader
        self.processReader = processReader
    }

    public func sample() async -> SamplePayload {
        SamplePayload(
            battery: batteryReader.read(),
            system: systemReader.read(),
            processes: processReader.read()
        )
    }
}
