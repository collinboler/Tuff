import DeviceActivity
import ManagedSettings
import Foundation

class TuffDeviceActivityMonitor: DeviceActivityMonitor {

    private let groupID = "group.com.collinboler.tuff"
    private let breakEndDateKey = "tuff_breakEndDate"

    /// Called at the start of each registered window.
    /// Handles both the hourly keep-alive schedules ("tuff.block.*") and the
    /// one-shot schedule registered at the exact break-end time ("tuff.breakEnd").
    /// Re-applies shields whenever no break is currently active.
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        let isHourly   = activity.rawValue.hasPrefix("tuff.block.")
        let isBreakEnd = activity.rawValue == "tuff.breakEnd"
        guard isHourly || isBreakEnd else { return }

        let defaults = UserDefaults(suiteName: groupID)
        // If a break is still in progress, don't re-lock
        if let breakEnd = defaults?.object(forKey: breakEndDateKey) as? Date,
           Date() < breakEnd {
            return
        }

        // Clear the break keys so the main app knows the break ended
        if isBreakEnd {
            defaults?.removeObject(forKey: breakEndDateKey)
            defaults?.removeObject(forKey: "tuff_breakStartDate")
        }

        // Re-apply shields
        let store = ManagedSettingsStore()
        store.shield.applicationCategories = .all()
        store.shield.webDomainCategories = .all()
        store.application.denyAppRemoval = true
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
    }
}
