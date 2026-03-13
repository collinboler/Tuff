import DeviceActivity
import ManagedSettings
import Foundation

/// App extension that runs in the background to monitor device activity.
/// Apple requires this as a separate target—it cannot live in the main app process.
///
/// To set up in Xcode:
/// 1. File > New > Target > Device Activity Monitor Extension
/// 2. Name it "TuffDeviceActivity"
/// 3. Add FamilyControls & DeviceActivity capabilities
class TuffDeviceActivityMonitor: DeviceActivityMonitor {

    let store = ManagedSettingsStore()

    /// Called when a monitored interval begins (e.g., start of day)
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Re-apply shields at the start of each monitoring interval
        // In production, fetch blocked apps from shared UserDefaults (App Group)
    }

    /// Called when a monitored interval ends (e.g., end of day)
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Daily interval ended: clear shields, log final screen time
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }

    /// Called when a usage threshold is reached for a specific app/category
    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        // The user exceeded their screen time threshold for a tracked app.
        // In production:
        // 1. Send push notification via backend
        // 2. Activate shields on the offending apps
        // 3. Trigger Friend 2FA or Custom Challenge flow
    }

    /// Called when usage drops below a previously-reached threshold
    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }
}
