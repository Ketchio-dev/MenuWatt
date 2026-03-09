import BoochiCore

public actor LiveMonitorSampler: MonitorSampling {
    private let batteryReader: LiveBatterySnapshotReader
    private let systemReader: LiveSystemSnapshotReader

    public init(
        batteryReader: LiveBatterySnapshotReader = LiveBatterySnapshotReader(),
        systemReader: LiveSystemSnapshotReader = LiveSystemSnapshotReader()
    ) {
        self.batteryReader = batteryReader
        self.systemReader = systemReader
    }

    public func sample() async -> SamplePayload {
        SamplePayload(
            battery: batteryReader.read(),
            system: systemReader.read()
        )
    }
}
