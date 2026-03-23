import Foundation
import CIOReport

struct SMCPowerSnapshot: Sendable {
    let systemPower: Double?
    let deliveryRate: Double?
}

final class IOReportPowerReader: @unchecked Sendable {
    func read() -> SMCPowerSnapshot {
        let reading = SMCReadPower()
        return SMCPowerSnapshot(
            systemPower: reading.systemPower >= 0 ? reading.systemPower : nil,
            deliveryRate: reading.deliveryRate >= 0 ? reading.deliveryRate : nil
        )
    }
}
