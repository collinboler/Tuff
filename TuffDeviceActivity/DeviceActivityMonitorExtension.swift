import DeviceActivity
import ManagedSettings
import Foundation

class TuffDeviceActivityMonitor: DeviceActivityMonitor {

    private let groupID = "group.com.collinboler.tuff"
    private let breakEndDateKey = "tuff_breakEndDate"

    /// Called at the start of each registered hourly window.
    /// Re-applies shields if no break is active — this keeps blocking alive
    /// even when the main app process has been killed by iOS.
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        guard activity.rawValue.hasPrefix("tuff.block.") else { return }

        let defaults = UserDefaults(suiteName: groupID)
        // If a break is still in progress, don't re-lock
        if let breakEnd = defaults?.object(forKey: breakEndDateKey) as? Date,
           Date() < breakEnd {
            return
        }

        // Re-apply shields — handles the case where the app was killed and
        // ManagedSettingsStore was cleared by iOS
        let store = ManagedSettingsStore()
        store.shield.applicationCategories = .all()
        store.shield.webDomainCategories = .all()
        store.application.denyAppRemoval = true
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
    }
}
