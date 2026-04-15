import Foundation

public struct HistoryBuffer: Sendable {
    public private(set) var samples: [Double] = []
    public let maxCount: Int

    public init(maxCount: Int = 30) {
        self.maxCount = maxCount
    }

    public mutating func append(_ value: Double) {
        if samples.count >= maxCount {
            samples.removeFirst()
        }
        samples.append(value)
    }
}

public struct SystemSnapshot: Sendable {
    public let cpu: CPUSnapshot
    public let memory: MemorySnapshot
    public let storage: StorageSnapshot
    public let gpu: GPUSnapshot
    public let fan: FanSnapshot
    public let network: NetworkSnapshot

    public init(
        cpu: CPUSnapshot,
        memory: MemorySnapshot,
        storage: StorageSnapshot,
        gpu: GPUSnapshot = .unavailable,
        fan: FanSnapshot = .unavailable,
        network: NetworkSnapshot = .unavailable
    ) {
        self.cpu = cpu
        self.memory = memory
        self.storage = storage
        self.gpu = gpu
        self.fan = fan
        self.network = network
    }

    public static let unavailable = SystemSnapshot(
        cpu: .unavailable,
        memory: .unavailable,
        storage: .unavailable,
        gpu: .unavailable,
        fan: .unavailable,
        network: .unavailable
    )
}

public struct GPUSnapshot: Sendable {
    public let isAvailable: Bool
    public let utilizationPercent: Double
    public let history: [Double]

    public init(utilizationPercent: Double, history: [Double], isAvailable: Bool = true) {
        self.isAvailable = isAvailable
        self.utilizationPercent = utilizationPercent
        self.history = history
    }

    public static let unavailable = GPUSnapshot(utilizationPercent: 0, history: [], isAvailable: false)

    public var titleValue: String {
        guard isAvailable else { return "Unavailable" }
        return String(format: "%.1f%%", utilizationPercent)
    }
}

public struct FanReading: Sendable, Identifiable, Equatable {
    public let index: Int
    public let rpm: Double
    public let maxRpm: Double?

    public var id: Int { index }

    public init(index: Int, rpm: Double, maxRpm: Double?) {
        self.index = index
        self.rpm = rpm
        self.maxRpm = maxRpm
    }

    public var percent: Double? {
        guard let maxRpm, maxRpm > 0 else { return nil }
        return min(max(rpm / maxRpm * 100, 0), 100)
    }
}

public struct FanSnapshot: Sendable {
    public let isAvailable: Bool
    public let fans: [FanReading]

    public init(fans: [FanReading], isAvailable: Bool = true) {
        self.isAvailable = isAvailable
        self.fans = fans
    }

    public static let unavailable = FanSnapshot(fans: [], isAvailable: false)

    public var titleValue: String {
        guard isAvailable, let first = fans.first else { return "Unavailable" }
        return String(format: "%.0f RPM", first.rpm)
    }
}

public struct NetworkSnapshot: Sendable {
    public let isAvailable: Bool
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double
    public let totalDownBytes: UInt64
    public let totalUpBytes: UInt64
    public let history: [Double]

    public init(
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double,
        totalDownBytes: UInt64,
        totalUpBytes: UInt64,
        history: [Double],
        isAvailable: Bool = true
    ) {
        self.isAvailable = isAvailable
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.totalDownBytes = totalDownBytes
        self.totalUpBytes = totalUpBytes
        self.history = history
    }

    public static let unavailable = NetworkSnapshot(
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0,
        totalDownBytes: 0,
        totalUpBytes: 0,
        history: [],
        isAvailable: false
    )

    public var titleValue: String {
        guard isAvailable else { return "Unavailable" }
        return Formatters.bytesPerSecond(downloadBytesPerSecond)
    }
}

public struct ProcessEnergyEntry: Sendable, Identifiable, Equatable {
    public let pid: Int32
    public let name: String
    public let bundleIdentifier: String?
    public let energyImpact: Double
    public let cpuPercent: Double

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, bundleIdentifier: String? = nil, energyImpact: Double, cpuPercent: Double) {
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.energyImpact = energyImpact
        self.cpuPercent = cpuPercent
    }
}

public struct ProcessEnergySnapshot: Sendable {
    public let isAvailable: Bool
    public let entries: [ProcessEnergyEntry]

    public init(entries: [ProcessEnergyEntry], isAvailable: Bool = true) {
        self.isAvailable = isAvailable
        self.entries = entries
    }

    public static let unavailable = ProcessEnergySnapshot(entries: [], isAvailable: false)
}

public struct NetworkCounters: Sendable, Equatable {
    public let downBytes: UInt64
    public let upBytes: UInt64

    public init(downBytes: UInt64, upBytes: UInt64) {
        self.downBytes = downBytes
        self.upBytes = upBytes
    }
}

public struct CPUSnapshot: Sendable {
    public let isAvailable: Bool
    public let totalUsage: Double
    public let userUsage: Double
    public let systemUsage: Double
    public let idleUsage: Double
    public let history: [Double]

    public init(
        totalUsage: Double,
        userUsage: Double,
        systemUsage: Double,
        idleUsage: Double,
        history: [Double],
        isAvailable: Bool = true
    ) {
        self.isAvailable = isAvailable
        self.totalUsage = totalUsage
        self.userUsage = userUsage
        self.systemUsage = systemUsage
        self.idleUsage = idleUsage
        self.history = history
    }

    public static let unavailable = CPUSnapshot(
        totalUsage: 0,
        userUsage: 0,
        systemUsage: 0,
        idleUsage: 100,
        history: [],
        isAvailable: false
    )

    public var titleValue: String {
        guard isAvailable else { return "Unavailable" }
        return String(format: "%.1f%%", totalUsage)
    }
}

public struct MemorySnapshot: Sendable {
    public let isAvailable: Bool
    public let usedPercent: Double
    public let pressurePercent: Double
    public let pressureLevel: PressureLevel
    public let usedBytes: UInt64
    public let appMemoryBytes: UInt64
    public let wiredMemoryBytes: UInt64
    public let compressedBytes: UInt64
    public let cachedFilesBytes: UInt64
    public let swapUsedBytes: UInt64
    public let pressureHistory: [Double]

    public init(
        usedPercent: Double,
        pressurePercent: Double,
        pressureLevel: PressureLevel,
        usedBytes: UInt64,
        appMemoryBytes: UInt64,
        wiredMemoryBytes: UInt64,
        compressedBytes: UInt64,
        cachedFilesBytes: UInt64,
        swapUsedBytes: UInt64,
        pressureHistory: [Double],
        isAvailable: Bool = true
    ) {
        self.isAvailable = isAvailable
        self.usedPercent = usedPercent
        self.pressurePercent = pressurePercent
        self.pressureLevel = pressureLevel
        self.usedBytes = usedBytes
        self.appMemoryBytes = appMemoryBytes
        self.wiredMemoryBytes = wiredMemoryBytes
        self.compressedBytes = compressedBytes
        self.cachedFilesBytes = cachedFilesBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressureHistory = pressureHistory
    }

    public static let unavailable = MemorySnapshot(
        usedPercent: 0,
        pressurePercent: 0,
        pressureLevel: .normal,
        usedBytes: 0,
        appMemoryBytes: 0,
        wiredMemoryBytes: 0,
        compressedBytes: 0,
        cachedFilesBytes: 0,
        swapUsedBytes: 0,
        pressureHistory: [],
        isAvailable: false
    )

    public var titleValue: String {
        guard isAvailable else { return "Unavailable" }
        return String(format: "%.1f%%", usedPercent)
    }
}

public struct StorageSnapshot: Sendable {
    public let isAvailable: Bool
    public let usedPercent: Double
    public let usedBytes: UInt64
    public let totalBytes: UInt64

    public init(usedPercent: Double, usedBytes: UInt64, totalBytes: UInt64, isAvailable: Bool = true) {
        self.isAvailable = isAvailable
        self.usedPercent = usedPercent
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    public static let unavailable = StorageSnapshot(usedPercent: 0, usedBytes: 0, totalBytes: 0, isAvailable: false)

    public var titleValue: String {
        guard isAvailable else { return "Unavailable" }
        return String(format: "%.1f%% used", usedPercent)
    }
}

public enum PressureLevel: Int, Sendable {
    case normal = 1
    case warn = 2
    case critical = 4

    public var title: String {
        switch self {
        case .normal:
            return "Normal"
        case .warn:
            return "Warning"
        case .critical:
            return "Critical"
        }
    }
}

public struct CPUCounters: Sendable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public struct MemoryStats: Sendable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let appMemoryBytes: UInt64
    public let wiredMemoryBytes: UInt64
    public let compressedBytes: UInt64
    public let cachedFilesBytes: UInt64
    public let freeBytes: UInt64
    public let swapUsedBytes: UInt64

    public init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        appMemoryBytes: UInt64,
        wiredMemoryBytes: UInt64,
        compressedBytes: UInt64,
        cachedFilesBytes: UInt64,
        freeBytes: UInt64,
        swapUsedBytes: UInt64
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.appMemoryBytes = appMemoryBytes
        self.wiredMemoryBytes = wiredMemoryBytes
        self.compressedBytes = compressedBytes
        self.cachedFilesBytes = cachedFilesBytes
        self.freeBytes = freeBytes
        self.swapUsedBytes = swapUsedBytes
    }
}

public struct StorageStats: Sendable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64

    public init(usedBytes: UInt64, totalBytes: UInt64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }
}

private final class ByteCountFormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    func string(from value: UInt64) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(fromByteCount: Int64(value))
    }
}

public enum Formatters {
    private static let byteCountFormatterCache = ByteCountFormatterCache()

    public static func bytes(_ value: UInt64) -> String {
        byteCountFormatterCache.string(from: value)
    }

    public static func bytesPerSecond(_ value: Double) -> String {
        let clamped = max(0, value)
        let rounded = UInt64(min(clamped, Double(UInt64.max)))
        return "\(byteCountFormatterCache.string(from: rounded))/s"
    }
}
