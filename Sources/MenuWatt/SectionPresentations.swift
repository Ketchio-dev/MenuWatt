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
