import Foundation
import IOKit.ps

enum PowerMonitor {
    static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return false
        }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                if let state = info[kIOPSPowerSourceStateKey] as? String {
                    return state == kIOPSBatteryPowerValue
                }
            }
        }
        return false
    }
}
