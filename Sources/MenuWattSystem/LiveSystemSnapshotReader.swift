import Darwin
import Foundation
import IOKit
import MenuWattCore
import CIOReport

public final class LiveSystemSnapshotReader {
    struct Readers: Sendable {
        let readCPUCounters: @Sendable () -> CPUCounters?
        let readMemoryStats: @Sendable () -> MemoryStats?
        let readStorageStats: @Sendable () -> StorageStats?
        let readKernelPressureLevel: @Sendable () -> PressureLevel
        let readGPUUtilization: @Sendable () -> Double?
        let readFans: @Sendable () -> [FanReading]?
        let readNetworkCounters: @Sendable () -> NetworkCounters?

        static let live = Readers(
            readCPUCounters: SystemReaders.readCPUCounters,
            readMemoryStats: SystemReaders.readMemoryStats,
            readStorageStats: SystemReaders.readStorageStats,
            readKernelPressureLevel: SystemReaders.readKernelPressureLevel,
            readGPUUtilization: SystemReaders.readGPUUtilization,
            readFans: SystemReaders.readFans,
            readNetworkCounters: SystemReaders.readNetworkCounters
        )
    }

    private var previousCPUCounters: CPUCounters?
    private var cpuHistory = HistoryBuffer()
    private var pressureHistory = HistoryBuffer()
    private var gpuHistory = HistoryBuffer()
    private var networkHistory = HistoryBuffer()
    private var previousNetworkCounters: NetworkCounters?
    private var previousNetworkTimestamp: TimeInterval?
    private let readers: Readers
    private let clock: @Sendable () -> TimeInterval

    public init() {
        self.readers = .live
        self.clock = { Date().timeIntervalSince1970 }
        self.previousCPUCounters = readers.readCPUCounters()
        self.previousNetworkCounters = readers.readNetworkCounters()
        self.previousNetworkTimestamp = clock()
    }

    init(readers: Readers, clock: @Sendable @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.readers = readers
        self.clock = clock
        self.previousCPUCounters = readers.readCPUCounters()
        self.previousNetworkCounters = readers.readNetworkCounters()
        self.previousNetworkTimestamp = clock()
    }

    public func read() -> SystemSnapshot {
        SystemSnapshot(
            cpu: readCPU(),
            memory: readMemory(),
            storage: readStorage(),
            gpu: readGPU(),
            fan: readFan(),
            network: readNetwork()
        )
    }

    private func readCPU() -> CPUSnapshot {
        guard let counters = readers.readCPUCounters() else {
            return .unavailable
        }
        defer { previousCPUCounters = counters }

        guard let previousCPUCounters else {
            return .unavailable
        }

        let userDelta = max(0, counters.user - previousCPUCounters.user)
        let systemDelta = max(0, counters.system - previousCPUCounters.system)
        let idleDelta = max(0, counters.idle - previousCPUCounters.idle)
        let niceDelta = max(0, counters.nice - previousCPUCounters.nice)
        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta

        guard totalDelta > 0 else {
            cpuHistory.append(0)
            return CPUSnapshot(
                totalUsage: 0,
                userUsage: 0,
                systemUsage: 0,
                idleUsage: 100,
                history: cpuHistory.samples
            )
        }

        let userUsage = Double(userDelta + niceDelta) / Double(totalDelta) * 100
        let systemUsage = Double(systemDelta) / Double(totalDelta) * 100
        let idleUsage = Double(idleDelta) / Double(totalDelta) * 100
        let totalUsage = max(0, 100 - idleUsage)
        cpuHistory.append(totalUsage)

        return CPUSnapshot(
            totalUsage: totalUsage,
            userUsage: userUsage,
            systemUsage: systemUsage,
            idleUsage: idleUsage,
            history: cpuHistory.samples
        )
    }

    private func readMemory() -> MemorySnapshot {
        guard let stats = readers.readMemoryStats() else {
            return .unavailable
        }

        let total = Double(stats.totalBytes)
        guard total > 0 else {
            return .unavailable
        }

        let usedPercent = Double(stats.usedBytes) / total * 100
        let pressurePercent = memoryPressurePercent(for: stats)
        let pressureLevel = readers.readKernelPressureLevel()

        pressureHistory.append(pressurePercent)

        return MemorySnapshot(
            usedPercent: usedPercent,
            pressurePercent: pressurePercent,
            pressureLevel: pressureLevel,
            usedBytes: stats.usedBytes,
            appMemoryBytes: stats.appMemoryBytes,
            wiredMemoryBytes: stats.wiredMemoryBytes,
            compressedBytes: stats.compressedBytes,
            cachedFilesBytes: stats.cachedFilesBytes,
            swapUsedBytes: stats.swapUsedBytes,
            pressureHistory: pressureHistory.samples
        )
    }

    private func readStorage() -> StorageSnapshot {
        guard let stats = readers.readStorageStats() else {
            return .unavailable
        }

        let total = Double(stats.totalBytes)
        guard total > 0 else {
            return .unavailable
        }

        let usedPercent = Double(stats.usedBytes) / total * 100
        return StorageSnapshot(usedPercent: usedPercent, usedBytes: stats.usedBytes, totalBytes: stats.totalBytes)
    }

    private func readGPU() -> GPUSnapshot {
        guard let utilization = readers.readGPUUtilization() else {
            return .unavailable
        }
        let clamped = min(max(utilization, 0), 100)
        gpuHistory.append(clamped)
        return GPUSnapshot(utilizationPercent: clamped, history: gpuHistory.samples)
    }

    private func readFan() -> FanSnapshot {
        guard let fans = readers.readFans(), !fans.isEmpty else {
            return .unavailable
        }
        return FanSnapshot(fans: fans)
    }

    private func readNetwork() -> NetworkSnapshot {
        guard let counters = readers.readNetworkCounters() else {
            return .unavailable
        }
        let now = clock()
        defer {
            previousNetworkCounters = counters
            previousNetworkTimestamp = now
        }

        guard
            let previous = previousNetworkCounters,
            let previousTimestamp = previousNetworkTimestamp
        else {
            networkHistory.append(0)
            return NetworkSnapshot(
                downloadBytesPerSecond: 0,
                uploadBytesPerSecond: 0,
                totalDownBytes: counters.downBytes,
                totalUpBytes: counters.upBytes,
                history: networkHistory.samples
            )
        }

        let elapsed = max(now - previousTimestamp, 0.001)
        let downDelta = counters.downBytes >= previous.downBytes ? counters.downBytes - previous.downBytes : 0
        let upDelta = counters.upBytes >= previous.upBytes ? counters.upBytes - previous.upBytes : 0
        let downRate = Double(downDelta) / elapsed
        let upRate = Double(upDelta) / elapsed
        networkHistory.append(downRate + upRate)

        return NetworkSnapshot(
            downloadBytesPerSecond: downRate,
            uploadBytesPerSecond: upRate,
            totalDownBytes: counters.downBytes,
            totalUpBytes: counters.upBytes,
            history: networkHistory.samples
        )
    }

    private func memoryPressurePercent(for stats: MemoryStats) -> Double {
        let total = Double(stats.totalBytes)
        guard total > 0 else { return 0 }

        let headroomPercent = Double(stats.cachedFilesBytes + stats.freeBytes) / total * 100
        let compressedPercent = Double(stats.compressedBytes) / total * 100
        let swapPercent = Double(stats.swapUsedBytes) / total * 100

        let scarcity = max(0, 100 - headroomPercent * 1.35)
        let compressionPenalty = compressedPercent * 0.55
        let swapPenalty = swapPercent * 2.2

        return min(max(scarcity * 0.55 + compressionPenalty + swapPenalty, 0), 100)
    }
}

private enum SystemReaders {
    static func readCPUCounters() -> CPUCounters? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        return CPUCounters(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    static func readMemoryStats() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let pageBytes = UInt64(pageSize)
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let appMemoryBytes = UInt64(stats.internal_page_count) * pageBytes
        let wiredMemoryBytes = UInt64(stats.wire_count) * pageBytes
        let compressedBytes = UInt64(stats.compressor_page_count) * pageBytes
        let cachedFilesBytes = UInt64(stats.external_page_count + stats.purgeable_count) * pageBytes
        let freeBytes = UInt64(stats.free_count + stats.speculative_count) * pageBytes
        let usedBytes = appMemoryBytes + wiredMemoryBytes + compressedBytes
        let swapUsedBytes = readSwapUsageBytes() ?? 0

        return MemoryStats(
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            appMemoryBytes: appMemoryBytes,
            wiredMemoryBytes: wiredMemoryBytes,
            compressedBytes: compressedBytes,
            cachedFilesBytes: cachedFilesBytes,
            freeBytes: freeBytes,
            swapUsedBytes: swapUsedBytes
        )
    }

    static func readStorageStats() -> StorageStats? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = (attributes[.systemSize] as? NSNumber)?.uint64Value,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value else {
            return nil
        }

        return StorageStats(usedBytes: total - free, totalBytes: total)
    }

    static func readKernelPressureLevel() -> PressureLevel {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.stride

        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        guard result == 0 else { return .normal }

        switch level {
        case 4:
            return .critical
        case 2:
            return .warn
        default:
            return .normal
        }
    }

    static func readGPUUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let props = IORegistryEntryCreateCFProperty(
                entry,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            let candidateKeys = ["Device Utilization %", "GPU Activity(%)", "GPU Core Utilization"]
            for key in candidateKeys {
                if let number = props[key] as? NSNumber {
                    let value = number.doubleValue
                    // GPU Core Utilization is reported in nanoseconds-busy — skip that scale.
                    if key == "GPU Core Utilization" && value > 100 {
                        continue
                    }
                    if best == nil || value > best! {
                        best = value
                    }
                    break
                }
            }
        }

        return best
    }

    static func readFans() -> [FanReading]? {
        let reading = SMCReadFans()
        var result: [FanReading] = []

        if reading.fan0Rpm >= 0 {
            let maxRpm = reading.fan0MaxRpm > 0 ? reading.fan0MaxRpm : nil
            result.append(FanReading(index: 0, rpm: reading.fan0Rpm, maxRpm: maxRpm))
        }
        if reading.fan1Rpm >= 0 {
            let maxRpm = reading.fan1MaxRpm > 0 ? reading.fan1MaxRpm : nil
            result.append(FanReading(index: 1, rpm: reading.fan1Rpm, maxRpm: maxRpm))
        }

        return result.isEmpty ? nil : result
    }

    static func readNetworkCounters() -> NetworkCounters? {
        var ifapPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifapPointer) == 0, let first = ifapPointer else {
            return nil
        }
        defer { freeifaddrs(first) }

        var totalDown: UInt64 = 0
        var totalUp: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = current {
            let ifa = ptr.pointee
            current = ifa.ifa_next

            guard let addr = ifa.ifa_addr else { continue }
            guard Int32(addr.pointee.sa_family) == AF_LINK else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard (flags & IFF_UP) != 0 else { continue }
            guard (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let dataPointer = ifa.ifa_data else { continue }

            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            totalDown &+= UInt64(data.ifi_ibytes)
            totalUp &+= UInt64(data.ifi_obytes)
        }

        return NetworkCounters(downBytes: totalDown, upBytes: totalUp)
    }

    private static func readSwapUsageBytes() -> UInt64? {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride

        let result = withUnsafeMutablePointer(to: &swap) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: size) {
                sysctlbyname("vm.swapusage", $0, &size, nil, 0)
            }
        }

        guard result == 0 else { return nil }
        return swap.xsu_used
    }
}
