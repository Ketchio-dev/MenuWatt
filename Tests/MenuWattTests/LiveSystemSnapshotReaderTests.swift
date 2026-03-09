import Foundation
import Testing
@testable import MenuWattCore
@testable import MenuWattSystem

private final class CPUCountersQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CPUCounters?]

    init(_ values: [CPUCounters?]) {
        self.values = values
    }

    func next() -> CPUCounters? {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty ? nil : values.removeFirst()
    }
}

@Test
func cpuIsPrimedDuringInitializationSoFirstReadProducesUsage() {
    let countersQueue = CPUCountersQueue([
        CPUCounters(user: 100, system: 50, idle: 200, nice: 10),
        CPUCounters(user: 125, system: 70, idle: 220, nice: 15)
    ])

    let reader = LiveSystemSnapshotReader(
        readers: .init(
            readCPUCounters: { countersQueue.next() },
            readMemoryStats: {
                MemoryStats(
                    totalBytes: 100,
                    usedBytes: 40,
                    appMemoryBytes: 20,
                    wiredMemoryBytes: 10,
                    compressedBytes: 10,
                    cachedFilesBytes: 30,
                    freeBytes: 30,
                    swapUsedBytes: 0
                )
            },
            readStorageStats: { StorageStats(usedBytes: 60, totalBytes: 100) },
            readKernelPressureLevel: { .normal }
        )
    )

    let snapshot = reader.read()

    #expect(snapshot.cpu.isAvailable)
    #expect(snapshot.cpu.history.count == 1)
    #expect(abs(snapshot.cpu.totalUsage - 71.4285714286) < 0.001)
}

@Test
func memoryAndStorageBecomeUnavailableWhenReadersFailIndependently() {
    let countersQueue = CPUCountersQueue([
        CPUCounters(user: 10, system: 10, idle: 80, nice: 0),
        CPUCounters(user: 20, system: 15, idle: 85, nice: 0)
    ])

    let reader = LiveSystemSnapshotReader(
        readers: .init(
            readCPUCounters: { countersQueue.next() },
            readMemoryStats: { nil },
            readStorageStats: { nil },
            readKernelPressureLevel: { .warn }
        )
    )

    let snapshot = reader.read()

    #expect(snapshot.cpu.isAvailable)
    #expect(!snapshot.memory.isAvailable)
    #expect(snapshot.memory.titleValue == "Unavailable")
    #expect(!snapshot.storage.isAvailable)
    #expect(snapshot.storage.titleValue == "Unavailable")
}
