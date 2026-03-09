import Testing
@testable import MenuWattCore

@Test
func unavailableSnapshotsExposeUnavailableState() {
    #expect(!CPUSnapshot.unavailable.isAvailable)
    #expect(CPUSnapshot.unavailable.titleValue == "Unavailable")

    #expect(!MemorySnapshot.unavailable.isAvailable)
    #expect(MemorySnapshot.unavailable.titleValue == "Unavailable")

    #expect(!StorageSnapshot.unavailable.isAvailable)
    #expect(StorageSnapshot.unavailable.titleValue == "Unavailable")
}

@Test
func availableSnapshotsKeepFormattedTitleValues() {
    let cpu = CPUSnapshot(
        totalUsage: 12.34,
        userUsage: 8,
        systemUsage: 4.34,
        idleUsage: 87.66,
        history: [12.34]
    )
    let memory = MemorySnapshot(
        usedPercent: 67.89,
        pressurePercent: 25,
        pressureLevel: .warn,
        usedBytes: 1,
        appMemoryBytes: 1,
        wiredMemoryBytes: 1,
        compressedBytes: 1,
        cachedFilesBytes: 1,
        swapUsedBytes: 0,
        pressureHistory: [25]
    )
    let storage = StorageSnapshot(usedPercent: 54.32, usedBytes: 1, totalBytes: 2)

    #expect(cpu.isAvailable)
    #expect(cpu.titleValue == "12.3%")

    #expect(memory.isAvailable)
    #expect(memory.titleValue == "67.9%")

    #expect(storage.isAvailable)
    #expect(storage.titleValue == "54.3% used")
}
