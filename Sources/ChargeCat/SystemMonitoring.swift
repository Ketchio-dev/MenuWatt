import Darwin
import SwiftUI

struct HistoryBuffer {
    private(set) var samples: [Double] = []
    let maxCount: Int

    init(maxCount: Int = 30) {
        self.maxCount = maxCount
    }

    mutating func append(_ value: Double) {
        if samples.count >= maxCount {
            samples.removeFirst()
        }
        samples.append(value)
    }
}

struct SystemSnapshot: Sendable {
    let cpu: CPUSnapshot
    let memory: MemorySnapshot
    let storage: StorageSnapshot

    static let unavailable = SystemSnapshot(
        cpu: .unavailable,
        memory: .unavailable,
        storage: .unavailable
    )
}

struct CPUSnapshot: Sendable {
    let totalUsage: Double
    let userUsage: Double
    let systemUsage: Double
    let idleUsage: Double
    let history: [Double]

    static let unavailable = CPUSnapshot(totalUsage: 0, userUsage: 0, systemUsage: 0, idleUsage: 100, history: [])

    var titleValue: String {
        String(format: "%.1f%%", totalUsage)
    }

    var detailLines: [String] {
        [
            String(format: "System: %.1f%%", systemUsage),
            String(format: "User: %.1f%%", userUsage),
            String(format: "Idle: %.1f%%", idleUsage)
        ]
    }
}

struct MemorySnapshot: Sendable {
    let usedPercent: Double
    let pressurePercent: Double
    let pressureLevel: PressureLevel
    let usedBytes: UInt64
    let appMemoryBytes: UInt64
    let wiredMemoryBytes: UInt64
    let compressedBytes: UInt64
    let cachedFilesBytes: UInt64
    let swapUsedBytes: UInt64
    let pressureHistory: [Double]

    static let unavailable = MemorySnapshot(
        usedPercent: 0,
        pressurePercent: 0,
        pressureLevel: .normal,
        usedBytes: 0,
        appMemoryBytes: 0,
        wiredMemoryBytes: 0,
        compressedBytes: 0,
        cachedFilesBytes: 0,
        swapUsedBytes: 0,
        pressureHistory: []
    )

    var titleValue: String {
        String(format: "%.1f%%", usedPercent)
    }

    var detailLines: [String] {
        [
            "Pressure: \(pressureLevel.title)",
            "Memory used: \(Formatters.bytes(usedBytes))",
            "App memory: \(Formatters.bytes(appMemoryBytes))",
            "Wired memory: \(Formatters.bytes(wiredMemoryBytes))",
            "Compressed: \(Formatters.bytes(compressedBytes))",
            "Cached files: \(Formatters.bytes(cachedFilesBytes))",
            "Swap used: \(Formatters.bytes(swapUsedBytes))"
        ]
    }
}

struct StorageSnapshot: Sendable {
    let usedPercent: Double
    let usedBytes: UInt64
    let totalBytes: UInt64

    static let unavailable = StorageSnapshot(usedPercent: 0, usedBytes: 0, totalBytes: 0)

    var titleValue: String {
        String(format: "%.1f%% used", usedPercent)
    }

    var detailLines: [String] {
        [
            "\(Formatters.bytes(usedBytes)) / \(Formatters.bytes(totalBytes))"
        ]
    }
}

enum PressureLevel: Int, Sendable {
    case normal = 1
    case warn = 2
    case critical = 4

    var title: String {
        switch self {
        case .normal:
            return "Normal"
        case .warn:
            return "Warning"
        case .critical:
            return "Critical"
        }
    }

    var themeColor: Color {
        switch self {
        case .normal:
            return .green
        case .warn:
            return .yellow
        case .critical:
            return .red
        }
    }
}

final class SystemSampler {
    private var previousCPUCounters: CPUCounters?
    private var cpuHistory = HistoryBuffer()
    private var pressureHistory = HistoryBuffer()

    func read() -> SystemSnapshot {
        let cpu = readCPU()
        let memory = readMemory()
        let storage = readStorage()

        return SystemSnapshot(cpu: cpu, memory: memory, storage: storage)
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

struct CPUCounters: Sendable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
}

struct MemoryStats: Sendable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let appMemoryBytes: UInt64
    let wiredMemoryBytes: UInt64
    let compressedBytes: UInt64
    let cachedFilesBytes: UInt64
    let freeBytes: UInt64
    let swapUsedBytes: UInt64
}

struct StorageStats: Sendable {
    let usedBytes: UInt64
    let totalBytes: UInt64
}

enum SystemReaders {
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

enum Formatters {
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(value))
    }
}
