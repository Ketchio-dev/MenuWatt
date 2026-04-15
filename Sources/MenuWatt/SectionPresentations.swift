import MenuWattCore

struct CPUSectionPresentation: Equatable {
    let titleValue: String
    let showsProgress: Bool
    let showsMetrics: Bool
    let showsHistory: Bool
    let unavailableMessage: String?

    static func make(from snapshot: CPUSnapshot) -> CPUSectionPresentation {
        guard snapshot.isAvailable else {
            return CPUSectionPresentation(
                titleValue: snapshot.titleValue,
                showsProgress: false,
                showsMetrics: false,
                showsHistory: false,
                unavailableMessage: "CPU usage data is unavailable."
            )
        }

        return CPUSectionPresentation(
            titleValue: snapshot.titleValue,
            showsProgress: true,
            showsMetrics: true,
            showsHistory: !snapshot.history.isEmpty,
            unavailableMessage: nil
        )
    }
}

struct MemorySectionPresentation: Equatable {
    let titleValue: String
    let showsPressureBadge: Bool
    let showsProgress: Bool
    let showsMetrics: Bool
    let unavailableMessage: String?

    static func make(from snapshot: MemorySnapshot) -> MemorySectionPresentation {
        guard snapshot.isAvailable else {
            return MemorySectionPresentation(
                titleValue: snapshot.titleValue,
                showsPressureBadge: false,
                showsProgress: false,
                showsMetrics: false,
                unavailableMessage: "Memory data is unavailable."
            )
        }

        return MemorySectionPresentation(
            titleValue: snapshot.titleValue,
            showsPressureBadge: true,
            showsProgress: true,
            showsMetrics: true,
            unavailableMessage: nil
        )
    }
}

struct GPUSectionPresentation: Equatable {
    let titleValue: String
    let showsProgress: Bool
    let showsHistory: Bool
    let unavailableMessage: String?

    static func make(from snapshot: GPUSnapshot) -> GPUSectionPresentation {
        guard snapshot.isAvailable else {
            return GPUSectionPresentation(
                titleValue: snapshot.titleValue,
                showsProgress: false,
                showsHistory: false,
                unavailableMessage: "GPU usage data is unavailable."
            )
        }

        return GPUSectionPresentation(
            titleValue: snapshot.titleValue,
            showsProgress: true,
            showsHistory: !snapshot.history.isEmpty,
            unavailableMessage: nil
        )
    }
}

struct FanSectionPresentation: Equatable {
    let titleValue: String
    let fans: [FanReading]
    let unavailableMessage: String?

    static func make(from snapshot: FanSnapshot) -> FanSectionPresentation {
        guard snapshot.isAvailable, !snapshot.fans.isEmpty else {
            return FanSectionPresentation(
                titleValue: snapshot.titleValue,
                fans: [],
                unavailableMessage: "No fan sensors on this Mac."
            )
        }

        return FanSectionPresentation(
            titleValue: snapshot.titleValue,
            fans: snapshot.fans,
            unavailableMessage: nil
        )
    }
}

struct NetworkSectionPresentation: Equatable {
    let titleValue: String
    let downloadText: String
    let uploadText: String
    let totalsText: String
    let showsHistory: Bool
    let unavailableMessage: String?

    static func make(from snapshot: NetworkSnapshot) -> NetworkSectionPresentation {
        guard snapshot.isAvailable else {
            return NetworkSectionPresentation(
                titleValue: snapshot.titleValue,
                downloadText: "—",
                uploadText: "—",
                totalsText: "",
                showsHistory: false,
                unavailableMessage: "Network counters unavailable."
            )
        }

        return NetworkSectionPresentation(
            titleValue: snapshot.titleValue,
            downloadText: Formatters.bytesPerSecond(snapshot.downloadBytesPerSecond),
            uploadText: Formatters.bytesPerSecond(snapshot.uploadBytesPerSecond),
            totalsText: "↓ \(Formatters.bytes(snapshot.totalDownBytes))  ↑ \(Formatters.bytes(snapshot.totalUpBytes))",
            showsHistory: !snapshot.history.isEmpty,
            unavailableMessage: nil
        )
    }
}

struct ProcessEnergySectionPresentation: Equatable {
    let entries: [ProcessEnergyEntry]
    let unavailableMessage: String?
    let isHidden: Bool

    static func make(from snapshot: ProcessEnergySnapshot) -> ProcessEnergySectionPresentation {
        guard snapshot.isAvailable else {
            return ProcessEnergySectionPresentation(entries: [], unavailableMessage: nil, isHidden: true)
        }

        if snapshot.entries.isEmpty {
            return ProcessEnergySectionPresentation(
                entries: [],
                unavailableMessage: "Collecting samples…",
                isHidden: false
            )
        }

        return ProcessEnergySectionPresentation(entries: snapshot.entries, unavailableMessage: nil, isHidden: false)
    }
}

struct StorageSectionPresentation: Equatable {
    let titleValue: String
    let usageSummary: String?
    let showsProgress: Bool
    let unavailableMessage: String?

    static func make(from snapshot: StorageSnapshot) -> StorageSectionPresentation {
        guard snapshot.isAvailable else {
            return StorageSectionPresentation(
                titleValue: snapshot.titleValue,
                usageSummary: nil,
                showsProgress: false,
                unavailableMessage: "Storage data is unavailable."
            )
        }

        return StorageSectionPresentation(
            titleValue: snapshot.titleValue,
            usageSummary: "\(Formatters.bytes(snapshot.usedBytes)) / \(Formatters.bytes(snapshot.totalBytes))",
            showsProgress: true,
            unavailableMessage: nil
        )
    }
}
