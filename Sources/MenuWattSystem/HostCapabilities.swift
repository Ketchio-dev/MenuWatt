import Foundation
import IOKit.ps

/// Static facts about the host Mac that do not change while the app runs.
public enum HostCapabilities {
    /// Whether this Mac has an internal battery.
    ///
    /// `true` on notebooks (MacBook / MacBook Air / Pro); `false` on desktop
    /// Macs (Mac mini, Mac Studio, Mac Pro, iMac). Computed once on first use —
    /// battery presence is a hardware fact that never changes at runtime.
    public static let hasInternalBattery: Bool = detectInternalBattery()

    private static func detectInternalBattery() -> Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [AnyObject]

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if let type = description[kIOPSTypeKey as String] as? String,
               type == kIOPSInternalBatteryType {
                return true
            }
        }

        return false
    }
}
