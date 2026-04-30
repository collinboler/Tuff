import DeviceActivity
import FamilyControls
import ManagedSettings
import ActivityKit
import Foundation

class TuffDeviceActivityMonitor: DeviceActivityMonitor {

    private let groupID        = "group.com.collinboler.tuff"
    private let breakEndDateKey   = "tuff_breakEndDate"
    private let breakStartDateKey = "tuff_breakStartDate"

    /// Called at the start of each registered window.
    /// Handles both the 2-hour keep-alive schedules ("tuff.keepalive.*"),
    /// the legacy hourly slots ("tuff.block.*"), and the one-shot schedule
    /// registered at break-end time ("tuff.breakEnd").
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        reapplyShieldIfNeeded(reason: "intervalDidStart \(activity.rawValue)")
    }

    /// Also re-apply the shield when each window ENDS. This halves the
    /// worst-case "shield drifts off" window from 2 hours to 1 hour and is
    /// the documented mitigation for the "blocking fades away" symptom on
    /// real devices: the system can occasionally drop ManagedSettings
    /// configuration if the app+extension haven't refreshed it recently.
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        reapplyShieldIfNeeded(reason: "intervalDidEnd \(activity.rawValue)")
    }

    // MARK: - Shield re-apply

    /// Common shield-refresh logic shared between intervalDidStart and
    /// intervalDidEnd. Skips re-locking while a break is in progress so we
    /// never accidentally clobber an active break.
    private func reapplyShieldIfNeeded(reason: String) {
        let isKeepAlive = activityIsKeepAlive(reason: reason)
        let isBreakEnd  = reason.contains("tuff.breakEnd")
        guard isKeepAlive || isBreakEnd else { return }

        let defaults = UserDefaults(suiteName: groupID)

        if let breakEnd = defaults?.object(forKey: breakEndDateKey) as? Date,
           Date() < breakEnd {
            return
        }

        defaults?.removeObject(forKey: breakEndDateKey)
        defaults?.removeObject(forKey: breakStartDateKey)

        let store = ManagedSettingsStore()
        let allowedSelectionKey = "tuff_allowedAppSelection"
        var exemptTokens: Set<ApplicationToken> = []
        if let data = defaults?.data(forKey: allowedSelectionKey),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            exemptTokens = selection.applicationTokens
        }
        if exemptTokens.isEmpty {
            store.shield.applicationCategories = .all()
        } else {
            store.shield.applicationCategories = .all(except: exemptTokens)
        }
        store.shield.webDomainCategories   = .all()
        store.application.denyAppRemoval   = true

        endStaleLiveActivities()
    }

    private func activityIsKeepAlive(reason: String) -> Bool {
        reason.contains("tuff.keepalive.") || reason.contains("tuff.block.")
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
