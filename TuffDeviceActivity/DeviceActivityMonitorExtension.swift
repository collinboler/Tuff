import DeviceActivity
import ManagedSettings
import ActivityKit
import Foundation

class TuffDeviceActivityMonitor: DeviceActivityMonitor {

    private let groupID        = "group.com.collinboler.tuff"
    private let breakEndDateKey   = "tuff_breakEndDate"
    private let breakStartDateKey = "tuff_breakStartDate"

    /// Called at the start of each registered window.
    /// Handles both the 15-min keep-alive schedules ("tuff.block.*") and the
    /// one-shot schedule registered at break-end time ("tuff.breakEnd").
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        let isKeepAlive = activity.rawValue.hasPrefix("tuff.block.")
        let isBreakEnd  = activity.rawValue == "tuff.breakEnd"
        guard isKeepAlive || isBreakEnd else { return }

        let defaults = UserDefaults(suiteName: groupID)

        // If a break is still in progress, don't re-lock
        if let breakEnd = defaults?.object(forKey: breakEndDateKey) as? Date,
           Date() < breakEnd {
            return
        }

        // Clear break keys from shared UserDefaults so the main app
        // immediately sees a clean state when it next becomes active.
        defaults?.removeObject(forKey: breakEndDateKey)
        defaults?.removeObject(forKey: breakStartDateKey)

        // Re-apply ManagedSettings shields
        let store = ManagedSettingsStore()
        store.shield.applicationCategories = .all()
        store.shield.webDomainCategories   = .all()
        store.application.denyAppRemoval   = true

        // Transition the Live Activity from break state to locked state so
        // the Dynamic Island stops showing the spinner / stale countdown.
        endStaleLiveActivities()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
    }

    // MARK: - Live Activity cleanup

    private func endStaleLiveActivities() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let lockedState = BlockTimerAttributes.ContentState(
            isOnBreak: false,
            endDate:   Date.distantFuture,
            appCount:  0
        )
        let lockedContent = ActivityContent(state: lockedState, staleDate: nil)

        for activity in Activity<BlockTimerAttributes>.activities {
            // If the activity is in break state and the break has ended, switch it
            // to locked state. The main app will own it from there.
            if activity.content.state.isOnBreak {
                Task {
                    await activity.update(lockedContent)
                }
            }
        }
    }
}
