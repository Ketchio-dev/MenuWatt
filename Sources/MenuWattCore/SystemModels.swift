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

    public init(cpu: CPUSnapshot, memory: MemorySnapshot, storage: StorageSnapshot) {
        self.cpu = cpu
        self.memory = memory
        self.storage = storage
    }

    public static let unavailable = SystemSnapshot(
        cpu: .unavailable,
        memory: .unavailable,
        storage: .unavailable
    )
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
}
