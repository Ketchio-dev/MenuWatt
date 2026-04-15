import Darwin
import Foundation
import MenuWattCore

/// Snapshot of per-process resource counters captured at a point in time.
public struct ProcessEnergyCounters: Sendable, Equatable {
    public let pid: Int32
    public let name: String
    public let userTimeNs: UInt64
    public let systemTimeNs: UInt64
    public let interruptWakeups: UInt64
    public let idleWakeups: UInt64

    public init(
        pid: Int32,
        name: String,
        userTimeNs: UInt64,
        systemTimeNs: UInt64,
        interruptWakeups: UInt64,
        idleWakeups: UInt64
    ) {
        self.pid = pid
        self.name = name
        self.userTimeNs = userTimeNs
        self.systemTimeNs = systemTimeNs
        self.interruptWakeups = interruptWakeups
        self.idleWakeups = idleWakeups
    }
}

public final class LiveProcessEnergyReader {
    struct Readers: Sendable {
        let listProcesses: @Sendable () -> [ProcessEnergyCounters]
        let clock: @Sendable () -> TimeInterval

        static let live = Readers(
            listProcesses: ProcessReaders.listProcesses,
            clock: { Date().timeIntervalSince1970 }
        )
    }

    // Public-ish energy-impact weighting. Activity Monitor does not publish its
    // exact formula; these weights approximate the relative contribution of CPU
    // time vs. wakeups described in Apple's "Energy Efficiency Guide" and are
    // intentionally tunable in one place.
    private static let cpuNsWeight = 1.0 / 1_000_000  // 1 per ms of CPU time
    private static let wakeupWeight = 0.5              // per wakeup
    private static let topCount = 5

    private let readers: Readers
    private var previousCounters: [Int32: ProcessEnergyCounters] = [:]
    private var previousTimestamp: TimeInterval?

    public init() {
        self.readers = .live
    }

    init(readers: Readers) {
        self.readers = readers
    }

    public func read() -> ProcessEnergySnapshot {
        let snapshot = readers.listProcesses()
        let now = readers.clock()
        defer {
            previousCounters = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.pid, $0) })
            previousTimestamp = now
        }

        guard let previousTimestamp, !previousCounters.isEmpty else {
            return ProcessEnergySnapshot(entries: [], isAvailable: true)
        }

        let elapsed = max(now - previousTimestamp, 0.001)

        var entries: [ProcessEnergyEntry] = []
        entries.reserveCapacity(snapshot.count)

        for counters in snapshot {
            guard let previous = previousCounters[counters.pid] else { continue }

            let cpuDelta = deltaNs(counters: counters, previous: previous)
            let wakeupDelta = deltaWakeups(counters: counters, previous: previous)

            let energyImpact = Double(cpuDelta) * Self.cpuNsWeight + Double(wakeupDelta) * Self.wakeupWeight
            let cpuPercent = Double(cpuDelta) / (elapsed * 1_000_000_000) * 100

            guard energyImpact > 0 else { continue }

            entries.append(
                ProcessEnergyEntry(
                    pid: counters.pid,
                    name: counters.name,
                    energyImpact: energyImpact,
                    cpuPercent: cpuPercent
                )
            )
        }

        entries.sort { $0.energyImpact > $1.energyImpact }
        if entries.count > Self.topCount {
            entries = Array(entries.prefix(Self.topCount))
        }

        return ProcessEnergySnapshot(entries: entries, isAvailable: true)
    }

    private func deltaNs(counters: ProcessEnergyCounters, previous: ProcessEnergyCounters) -> UInt64 {
        let userDelta = counters.userTimeNs >= previous.userTimeNs ? counters.userTimeNs - previous.userTimeNs : 0
        let systemDelta = counters.systemTimeNs >= previous.systemTimeNs ? counters.systemTimeNs - previous.systemTimeNs : 0
        return userDelta &+ systemDelta
    }

    private func deltaWakeups(counters: ProcessEnergyCounters, previous: ProcessEnergyCounters) -> UInt64 {
        let interruptDelta = counters.interruptWakeups >= previous.interruptWakeups
            ? counters.interruptWakeups - previous.interruptWakeups
            : 0
        let idleDelta = counters.idleWakeups >= previous.idleWakeups
            ? counters.idleWakeups - previous.idleWakeups
            : 0
        return interruptDelta &+ idleDelta
    }
}

private enum ProcessReaders {
    static func listProcesses() -> [ProcessEnergyCounters] {
        let needed = proc_listallpids(nil, 0)
        guard needed > 0 else { return [] }

        let slack = needed + 64
        var pids = [pid_t](repeating: 0, count: Int(slack))
        let byteCount = Int32(slack) * Int32(MemoryLayout<pid_t>.stride)
        let written = pids.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return 0 }
            return proc_listallpids(base, byteCount)
        }
        guard written > 0 else { return [] }
        let count = min(Int(written), pids.count)

        var results: [ProcessEnergyCounters] = []
        results.reserveCapacity(count)

        for index in 0..<count {
            let pid = pids[index]
            guard pid > 0 else { continue }
            guard let counters = counters(for: pid) else { continue }
            results.append(counters)
        }

        return results
    }

    private static func counters(for pid: pid_t) -> ProcessEnergyCounters? {
        var rusage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &rusage) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        guard result == 0 else { return nil }

        let name = processName(for: pid) ?? "pid \(pid)"

        return ProcessEnergyCounters(
            pid: pid,
            name: name,
            userTimeNs: rusage.ri_user_time,
            systemTimeNs: rusage.ri_system_time,
            interruptWakeups: rusage.ri_interrupt_wkups,
            idleWakeups: rusage.ri_pkg_idle_wkups
        )
    }

    private static func processName(for pid: pid_t) -> String? {
        let capacity = Int(MAXPATHLEN)
        var buffer = [CChar](repeating: 0, count: capacity)
        let length = buffer.withUnsafeMutableBufferPointer { bp -> Int32 in
            guard let base = bp.baseAddress else { return 0 }
            return proc_pidpath(pid, base, UInt32(capacity))
        }

        if length > 0 {
            let path = String(cString: buffer)
            if let last = path.split(separator: "/").last {
                return String(last)
            }
            return path
        }

        var nameBuffer = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN + 1))
        let nameLen = nameBuffer.withUnsafeMutableBufferPointer { bp -> Int32 in
            guard let base = bp.baseAddress else { return 0 }
            return proc_name(pid, base, UInt32(bp.count))
        }
        guard nameLen > 0 else { return nil }
        return String(cString: nameBuffer)
    }
}
