import Foundation
import Testing
@testable import MenuWattCore
@testable import MenuWattSystem

private final class ValueQueue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [T]

    init(_ values: [T]) {
        self.values = values
    }

    func next() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty ? nil : values.removeFirst()
    }
}

private final class TimeStub: @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeInterval

    init(_ start: TimeInterval) {
        self.current = start
    }

    func now() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ delta: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current += delta
    }
}

private func makeReaders(
    gpu: @escaping @Sendable () -> Double?,
    fans: @escaping @Sendable () -> [FanReading]?,
    network: @escaping @Sendable () -> NetworkInterfaceSnapshot?
) -> LiveSystemSnapshotReader.Readers {
    LiveSystemSnapshotReader.Readers(
        readCPUCounters: { CPUCounters(user: 0, system: 0, idle: 0, nice: 0) },
        readMemoryStats: { nil },
        readStorageStats: { nil },
        readKernelPressureLevel: { .normal },
        readGPUUtilization: gpu,
        readFans: fans,
        readNetworkCounters: network
    )
}

@Test
func networkBytesPerSecondUsesDeltasFromMatchingInterfaces() {
    let counters = ValueQueue([
        NetworkInterfaceSnapshot(interfaces: [1: .init(downBytes: 1_000, upBytes: 500),
                                              2: .init(downBytes: 8_000, upBytes: 8_000)])!,
        NetworkInterfaceSnapshot(interfaces: [1: .init(downBytes: 6_000, upBytes: 1_500),
                                              3: .init(downBytes: 5_000_000_000, upBytes: 9_000)])!,
        NetworkInterfaceSnapshot(interfaces: [1: .init(downBytes: 3, upBytes: 2_500),
                                              3: .init(downBytes: 5_000_000_200, upBytes: 9_000)])!
    ])
    let clock = TimeStub(0)

    let reader = LiveSystemSnapshotReader(
        readers: makeReaders(
            gpu: { 25 },
            fans: { [FanReading(index: 0, rpm: 1500, maxRpm: 5000)] },
            network: { counters.next() }
        ),
        clock: { clock.now() }
    )

    clock.advance(2)
    let changedInterfaces = reader.read().network
    #expect(changedInterfaces.isAvailable)
    #expect(changedInterfaces.downloadBytesPerSecond == 2500)
    #expect(changedInterfaces.uploadBytesPerSecond == 500)
    #expect(changedInterfaces.totalDownBytes == 5_000_006_000)
    clock.advance(2)
    let reset = reader.read().network
    #expect(reset.downloadBytesPerSecond == 100)
    #expect(reset.uploadBytesPerSecond == 500)
}

@Test
func gpuSnapshotIsUnavailableWhenReaderReturnsNil() {
    let reader = LiveSystemSnapshotReader(
        readers: makeReaders(
            gpu: { nil },
            fans: { nil },
            network: { nil }
        )
    )

    let snapshot = reader.read()

    #expect(!snapshot.gpu.isAvailable)
    #expect(snapshot.gpu.titleValue == "Unavailable")
}

@Test
func fanSnapshotIsUnavailableWhenNoFans() {
    let reader = LiveSystemSnapshotReader(
        readers: makeReaders(
            gpu: { 10 },
            fans: { [] },
            network: { nil }
        )
    )

    let snapshot = reader.read()

    #expect(!snapshot.fan.isAvailable)
    #expect(snapshot.fan.fans.isEmpty)
}

@Test
func gpuSnapshotClampsToHundred() {
    let reader = LiveSystemSnapshotReader(
        readers: makeReaders(
            gpu: { 250 },
            fans: { nil },
            network: { nil }
        )
    )

    let snapshot = reader.read()

    #expect(snapshot.gpu.isAvailable)
    #expect(snapshot.gpu.utilizationPercent == 100)
}
