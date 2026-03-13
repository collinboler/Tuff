import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings
import Combine

@MainActor
class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()

    @Published var isAuthorized = false
    @Published var selectedAppsToBlock: FamilyActivitySelection = FamilyActivitySelection()
    @Published var isMonitoring = false

    /// Filter used when requesting the DeviceActivityReport in StatsView
    var reportFilter: DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .daily(
                during: DateInterval(
                    start: Calendar.current.startOfDay(for: Date()),
                    end: Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
                )
            ),
            users: .all,
            devices: .init([.iPhone])
        )
    }

    private var store: ManagedSettingsStore?
    private var center: DeviceActivityCenter?

    private init() {
        store = ManagedSettingsStore()
        center = DeviceActivityCenter()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
            startMonitoring()
            print("[Tuff] Screen Time authorized ✓")
        } catch {
            print("[Tuff] Screen Time auth failed (needs Family Controls entitlement): \(error.localizedDescription)")
            isAuthorized = false
        }
    }

    // MARK: - App Blocking

    func blockSelectedApps() {
        guard isAuthorized, let store else { return }
        store.shield.applications = selectedAppsToBlock.applicationTokens.isEmpty
            ? nil : selectedAppsToBlock.applicationTokens
        store.shield.applicationCategories = selectedAppsToBlock.categoryTokens.isEmpty
            ? nil : .specific(selectedAppsToBlock.categoryTokens)
    }

    func unblockAllApps() {
        store?.shield.applications = nil
        store?.shield.applicationCategories = nil
    }

    func unblockWithFriend2FA(code: String, expectedCode: String) -> Bool {
        guard code == expectedCode else { return false }
        unblockAllApps()
        return true
    }

    // MARK: - Activity Monitoring

    func startMonitoring() {
        guard isAuthorized, let center else { return }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let activityName = DeviceActivityName(rawValue: "dailyActivity")
        do {
            try center.startMonitoring(activityName, during: schedule)
            isMonitoring = true
            print("[Tuff] Monitoring started ✓")
        } catch {
            print("[Tuff] Monitoring failed: \(error.localizedDescription)")
        }
    }

    func stopMonitoring() {
        center?.stopMonitoring([DeviceActivityName(rawValue: "dailyActivity")])
        isMonitoring = false
    }

    // MARK: - Screen Time Data
    // Reads from App Group (written by TuffActivityReport extension) when available,
    // falls back to sample data while the entitlement is pending.

    func fetchTodayScreenTime() -> TimeInterval {
        if let real = TuffSharedStore.todayScreenTime() {
            print("[Tuff] Using real screen time: \(real)s")
            return real
        }
        return 9420 // sample: 2h 37m
    }

    func fetchWeeklyData() -> [DailyScreenTime] {
        let history = TuffSharedStore.dailyHistory()
        guard !history.isEmpty else { return DailyScreenTime.sampleWeek }

        // Fill the last 7 days from real history, sample for any missing days
        let calendar = Calendar.current
        return (0..<7).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
            let dayStart = calendar.startOfDay(for: date)

            if let record = history.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
                return DailyScreenTime(
                    date: record.date,
                    totalSeconds: record.totalSeconds,
                    appBreakdown: record.appBreakdown.map {
                        AppUsage(appName: $0.displayName,
                                 bundleIdentifier: $0.bundleID,
                                 seconds: $0.totalSeconds,
                                 category: .other)
                    }
                )
            }
            // No data for this day yet — use sample
            let samples: [TimeInterval] = [9000, 7200, 10800, 8400, 10200, 6000, 7800]
            return DailyScreenTime(date: date, totalSeconds: samples[6 - daysAgo], appBreakdown: [])
        }
    }

    func fetchMonthlyData() -> [DailyScreenTime] {
        let history = TuffSharedStore.dailyHistory()
        guard !history.isEmpty else { return DailyScreenTime.sampleMonth }

        let calendar = Calendar.current
        return (0..<30).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
            if let record = history.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
                return DailyScreenTime(date: record.date, totalSeconds: record.totalSeconds, appBreakdown: [])
            }
            let base: TimeInterval = 8400
            let variance = Double((daysAgo * 7) % 3600) - 1800
            return DailyScreenTime(date: date, totalSeconds: max(3600, base + variance), appBreakdown: [])
        }
    }

    func fetchStats() -> ScreenTimeStats {
        let history = TuffSharedStore.dailyHistory()
        guard history.count >= 3 else { return DailyScreenTime.sampleStats }

        let times = history.map { $0.totalSeconds }
        let avg = times.reduce(0, +) / Double(times.count)
        let best = times.min() ?? 0
        let worst = times.max() ?? 0

        // Streak: consecutive days under 3h goal
        let goal: TimeInterval = 10800
        var streak = 0
        let sorted = history.sorted { $0.date > $1.date }
        for record in sorted {
            if record.totalSeconds < goal { streak += 1 } else { break }
        }

        return ScreenTimeStats(
            dailyAverage: avg,
            bestDay: best,
            worstDay: worst,
            currentStreak: streak,
            dailyGoal: goal
        )
    }
}
