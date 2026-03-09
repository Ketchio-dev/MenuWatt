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
