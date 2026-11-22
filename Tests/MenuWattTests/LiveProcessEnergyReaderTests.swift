import Foundation
import Testing
@testable import MenuWattCore
@testable import MenuWattSystem

private final class ListQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[ProcessEnergyCounters]]

    init(_ values: [[ProcessEnergyCounters]]) {
        self.values = values
    }

    func next() -> [ProcessEnergyCounters] {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty ? [] : values.removeFirst()
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

private func makeCounter(
    pid: Int32,
    name: String,
    user: UInt64 = 0,
    system: UInt64 = 0,
    interrupt: UInt64 = 0,
    idle: UInt64 = 0
) -> ProcessEnergyCounters {
    ProcessEnergyCounters(
        pid: pid,
        name: name,
        userTimeNs: user,
        systemTimeNs: system,
        interruptWakeups: interrupt,
        idleWakeups: idle
    )
}

@Test
func firstSampleProducesEmptyEntries() {
    let queue = ListQueue([
        [makeCounter(pid: 1, name: "a", user: 100)]
    ])
    let reader = LiveProcessEnergyReader(
        readers: .init(listProcesses: { queue.next() }, clock: { 0 })
    )

    let snapshot = reader.read()

    #expect(snapshot.isAvailable)
    #expect(snapshot.entries.isEmpty)
}

@Test
func secondSampleSortsByEnergyImpactAndCapsToFifteen() {
    let processIDs = (1...20).map(Int32.init)
    let queue = ListQueue([
        processIDs.map { makeCounter(pid: $0, name: "Process \($0)") },
        processIDs.map { makeCounter(pid: $0, name: "Process \($0)", user: UInt64($0) * 1_000_000) }
    ])
    let clock = TimeStub(0)
    let reader = LiveProcessEnergyReader(
        readers: .init(listProcesses: { queue.next() }, clock: { clock.now() })
    )

    _ = reader.read()
    clock.advance(1)
    let snapshot = reader.read()

    #expect(snapshot.entries.map(\.pid) == Array(processIDs.suffix(15).reversed()))
}

@Test
func disappearingPidsAreSkipped() {
    let queue = ListQueue([
        [
            makeCounter(pid: 1, name: "a"),
            makeCounter(pid: 2, name: "b")
        ],
        [
            makeCounter(pid: 2, name: "b", user: 5_000_000)
        ]
    ])
    let clock = TimeStub(0)
    let reader = LiveProcessEnergyReader(
        readers: .init(listProcesses: { queue.next() }, clock: { clock.now() })
    )

    _ = reader.read()
    clock.advance(1)
    let snapshot = reader.read()

    #expect(snapshot.entries.count == 1)
    #expect(snapshot.entries.first?.pid == 2)
}
