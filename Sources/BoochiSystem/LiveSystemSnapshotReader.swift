import Darwin
import Foundation
import MenuWattCore

public final class LiveSystemSnapshotReader {
    private var previousCPUCounters: CPUCounters?
    private var cpuHistory = HistoryBuffer()
    private var pressureHistory = HistoryBuffer()

    public init() {}

    public func read() -> SystemSnapshot {
        SystemSnapshot(
            cpu: readCPU(),
            memory: readMemory(),
            storage: readStorage()
        )
    }

    private func readCPU() -> CPUSnapshot {
        guard let counters = SystemReaders.readCPUCounters() else {
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
            return .unavailable
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
        guard let stats = SystemReaders.readMemoryStats() else {
            return .unavailable
        }

        let total = Double(stats.totalBytes)
        guard total > 0 else {
            return .unavailable
        }

        let usedPercent = Double(stats.usedBytes) / total * 100
        let pressurePercent = memoryPressurePercent(for: stats)
        let pressureLevel = SystemReaders.readKernelPressureLevel()

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
        guard let stats = SystemReaders.readStorageStats() else {
            return .unavailable
        }

        let total = Double(stats.totalBytes)
        guard total > 0 else {
            return .unavailable
        }

        let usedPercent = Double(stats.usedBytes) / total * 100
        return StorageSnapshot(usedPercent: usedPercent, usedBytes: stats.usedBytes, totalBytes: stats.totalBytes)
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
