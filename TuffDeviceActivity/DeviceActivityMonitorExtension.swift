import DeviceActivity
import FamilyControls
import ManagedSettings
import Foundation

class TuffDeviceActivityMonitor: DeviceActivityMonitor {

    let store = ManagedSettingsStore()
    private let ud = UserDefaults(suiteName: "group.com.collinboler.tuff")
    private let sharedTrackSelectionKey = "trackingFamilyActivitySelection"

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        ud?.set(Date().timeIntervalSince1970, forKey: "monitorLastStarted")
        ud?.removeObject(forKey: "lastThresholdFired")
        ud?.removeObject(forKey: "lastThresholdName")
        ud?.set(0, forKey: "thresholdFireCount")
        ud?.synchronize()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        snapshotTodayToHistory()
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)

        let rawName = event.rawValue

        ud?.set(Date().timeIntervalSince1970, forKey: "lastThresholdFired")
        ud?.set(rawName, forKey: "lastThresholdName")
        let count = (ud?.integer(forKey: "thresholdFireCount") ?? 0) + 1
        ud?.set(count, forKey: "thresholdFireCount")
        ud?.synchronize()

        if rawName.hasPrefix("screentime_"),
           let minutesStr = rawName.split(separator: "_").last,
           let minutes = Int(minutesStr) {
            let seconds = TimeInterval(minutes * 60)
            TuffSharedStore.saveTodayScreenTime(seconds)

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            var history = TuffSharedStore.dailyHistory()
            history.removeAll { calendar.isDate($0.date, inSameDayAs: today) }
            let record = DailyRecord(id: UUID(), date: today, totalSeconds: seconds, appBreakdown: [])
            history.append(record)
            let sorted = history.sorted { $0.date > $1.date }
            TuffSharedStore.saveDailyHistory(Array(sorted.prefix(30)))
            rearmNextThreshold(after: minutes, activity: activity)
        }
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }

    private func snapshotTodayToHistory() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let seconds = TuffSharedStore.todayScreenTime(), seconds > 0 else { return }
        var history = TuffSharedStore.dailyHistory()
        history.removeAll { calendar.isDate($0.date, inSameDayAs: today) }
        let breakdown = TuffSharedStore.appBreakdown()
        let record = DailyRecord(id: UUID(), date: today, totalSeconds: seconds, appBreakdown: breakdown)
        history.append(record)
        let sorted = history.sorted { $0.date > $1.date }
        TuffSharedStore.saveDailyHistory(Array(sorted.prefix(30)))
    }

    private func rearmNextThreshold(after minutes: Int, activity: DeviceActivityName) {
        guard let data = ud?.data(forKey: sharedTrackSelectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return
        }

        let appTokens = selection.applicationTokens
        let catTokens = selection.categoryTokens
        let webTokens = selection.webDomainTokens

        guard !appTokens.isEmpty || !catTokens.isEmpty || !webTokens.isEmpty else {
            return
        }

        let nextMinutes: Int
        if minutes < 10 {
            nextMinutes = minutes + 1
        } else {
            nextMinutes = ((minutes / 5) + 1) * 5
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )

        let eventName = DeviceActivityEvent.Name("screentime_\(nextMinutes)")
        let event: DeviceActivityEvent
        if #available(iOS 17.4, *) {
            event = DeviceActivityEvent(
                applications: appTokens,
                categories: catTokens,
                webDomains: webTokens,
                threshold: DateComponents(minute: nextMinutes),
                includesPastActivity: true
            )
        } else {
            event = DeviceActivityEvent(
                applications: appTokens,
                categories: catTokens,
                webDomains: webTokens,
                threshold: DateComponents(minute: nextMinutes)
            )
        }

        do {
            try DeviceActivityCenter().startMonitoring(activity, during: schedule, events: [eventName: event])
            ud?.set(nextMinutes, forKey: "nextThresholdMinutes")
            ud?.synchronize()
        } catch {
            ud?.set("rearm failed: \(error.localizedDescription)", forKey: "lastThresholdName")
            ud?.synchronize()
        }
    }
}
