import Testing
@testable import MenuWatt
@testable import MenuWattCore

@Test
func cpuPresentationReflectsAvailabilityAndHistory() {
    let available = CPUSectionPresentation.make(
        from: CPUSnapshot(
            totalUsage: 42,
            userUsage: 20,
            systemUsage: 22,
            idleUsage: 58,
            history: [10, 20, 42]
        )
    )
    let unavailable = CPUSectionPresentation.make(from: .unavailable)

    #expect(available.showsProgress)
    #expect(available.showsMetrics)
    #expect(available.showsHistory)
    #expect(available.unavailableMessage == nil)

    #expect(!unavailable.showsProgress)
    #expect(!unavailable.showsMetrics)
    #expect(!unavailable.showsHistory)
    #expect(unavailable.unavailableMessage == "CPU usage data is unavailable.")
}

@Test
func memoryAndStoragePresentationsHideUnavailableDetails() {
    let memoryUnavailable = MemorySectionPresentation.make(from: .unavailable)
    let storageUnavailable = StorageSectionPresentation.make(from: .unavailable)
    let storageAvailable = StorageSectionPresentation.make(
        from: StorageSnapshot(usedPercent: 50, usedBytes: 64 * 1024 * 1024 * 1024, totalBytes: 128 * 1024 * 1024 * 1024)
    )

    #expect(!memoryUnavailable.showsPressureBadge)
    #expect(!memoryUnavailable.showsProgress)
    #expect(!memoryUnavailable.showsMetrics)
    #expect(memoryUnavailable.unavailableMessage == "Memory data is unavailable.")

    #expect(storageUnavailable.usageSummary == nil)
    #expect(!storageUnavailable.showsProgress)
    #expect(storageUnavailable.unavailableMessage == "Storage data is unavailable.")

    #expect(storageAvailable.usageSummary != nil)
    #expect(storageAvailable.showsProgress)
    #expect(storageAvailable.unavailableMessage == nil)
}

@Test
func gpuPresentationReflectsAvailability() {
    let unavailable = GPUSectionPresentation.make(from: .unavailable)
    let available = GPUSectionPresentation.make(
        from: GPUSnapshot(utilizationPercent: 30, history: [10, 20, 30])
    )

    #expect(!unavailable.showsProgress)
    #expect(!unavailable.showsHistory)
    #expect(unavailable.unavailableMessage == "GPU usage data is unavailable.")

    #expect(available.showsProgress)
    #expect(available.showsHistory)
    #expect(available.unavailableMessage == nil)
}

@Test
func fanPresentationHidesEmptyFansAndShowsAvailable() {
    let unavailable = FanSectionPresentation.make(from: .unavailable)
    let available = FanSectionPresentation.make(
        from: FanSnapshot(fans: [FanReading(index: 0, rpm: 1500, maxRpm: 5000)])
    )

    #expect(unavailable.fans.isEmpty)
    #expect(unavailable.unavailableMessage != nil)

    #expect(available.fans.count == 1)
    #expect(available.unavailableMessage == nil)
}

@Test
func networkPresentationFormatsRatesAndTotals() {
    let unavailable = NetworkSectionPresentation.make(from: .unavailable)
    let available = NetworkSectionPresentation.make(
        from: NetworkSnapshot(
            downloadBytesPerSecond: 2_048,
            uploadBytesPerSecond: 1_024,
            totalDownBytes: 10_000_000,
            totalUpBytes: 5_000_000,
            history: [100, 200]
        )
    )

    #expect(unavailable.showsHistory == false)
    #expect(unavailable.unavailableMessage != nil)

    #expect(available.unavailableMessage == nil)
    #expect(available.showsHistory)
    #expect(available.downloadText.contains("/s"))
    #expect(!available.totalsText.isEmpty)
}

@Test
func processEnergyPresentationHidesWhenUnavailable() {
    let hidden = ProcessEnergySectionPresentation.make(from: .unavailable)
    let priming = ProcessEnergySectionPresentation.make(
        from: ProcessEnergySnapshot(entries: [], isAvailable: true)
    )
    let populated = ProcessEnergySectionPresentation.make(
        from: ProcessEnergySnapshot(entries: [
            ProcessEnergyEntry(pid: 1, name: "test", energyImpact: 5, cpuPercent: 1)
        ])
    )

    #expect(hidden.isHidden)
    #expect(!priming.isHidden)
    #expect(priming.unavailableMessage != nil)
    #expect(!populated.isHidden)
    #expect(populated.entries.count == 1)
}
