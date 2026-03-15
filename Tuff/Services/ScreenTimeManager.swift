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
        let status = AuthorizationCenter.shared.authorizationStatus
        print("[Tuff] Current auth status: \(status)")

        if status == .approved {
            isAuthorized = true
            print("[Tuff] Already authorized ✓")
            return
        }

        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
            startMonitoring()
            print("[Tuff] Screen Time authorized ✓")
        } catch {
            print("[Tuff] Screen Time auth failed: \(error)")
            isAuthorized = false
        }
    }

    // MARK: - App Blocking

    func blockSelectedApps() {
        guard let store else {
            print("[Tuff] blockSelectedApps: store is nil")
            return
        }

        let appTokens = selectedAppsToBlock.applicationTokens
        let catTokens = selectedAppsToBlock.categoryTokens
        print("[Tuff] blockSelectedApps: \(appTokens.count) apps, \(catTokens.count) categories, authorized=\(isAuthorized)")

        store.shield.applications = appTokens.isEmpty ? nil : appTokens
        store.shield.applicationCategories = catTokens.isEmpty ? nil : .specific(catTokens)

        print("[Tuff] Shield applied — apps: \(store.shield.applications?.count ?? 0), categories: \(store.shield.applicationCategories != nil)")
    }

    func unblockAllApps() {
        store?.clearAllSettings()
        print("[Tuff] All shields cleared")
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

    // MARK: - Screen Time Data (reads from App Groups, written by TuffActivityReport extension)

    struct RealDayEntry: Codable {
        let date: Date
        let totalSeconds: TimeInterval
    }

    private func loadRealHistory() -> [RealDayEntry] {
        guard let defaults = UserDefaults(suiteName: TuffSharedKeys.appGroupID),
              let data = defaults.data(forKey: "realDailyHistory"),
              let entries = try? JSONDecoder().decode([RealDayEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.date < $1.date }
    }

    func fetchWeeklyData() -> [DailyScreenTime] {
        let history = loadRealHistory()
        guard !history.isEmpty else { return DailyScreenTime.sampleWeek }

        let calendar = Calendar.current
        return (0..<7).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
            let dayStart = calendar.startOfDay(for: date)
            if let record = history.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
                return DailyScreenTime(date: record.date, totalSeconds: record.totalSeconds, appBreakdown: [])
            }
            return DailyScreenTime(date: date, totalSeconds: 0, appBreakdown: [])
        }
    }

    func fetchMonthlyData() -> [DailyScreenTime] {
        let history = loadRealHistory()
        guard !history.isEmpty else { return DailyScreenTime.sampleMonth }

        let calendar = Calendar.current
        return (0..<30).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
            let dayStart = calendar.startOfDay(for: date)
            if let record = history.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
                return DailyScreenTime(date: record.date, totalSeconds: record.totalSeconds, appBreakdown: [])
            }
            return DailyScreenTime(date: date, totalSeconds: 0, appBreakdown: [])
        }
    }

    func fetchStats(for period: Int = 7) -> ScreenTimeStats {
        let history = loadRealHistory()
        guard !history.isEmpty else { return DailyScreenTime.sampleStats }

        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -(period), to: calendar.startOfDay(for: Date()))!
        let periodEntries = history.filter { $0.date >= cutoff }
        let withActivity = periodEntries.filter { $0.totalSeconds > 0 }
        guard !withActivity.isEmpty else { return DailyScreenTime.sampleStats }

        let times = withActivity.map { $0.totalSeconds }
        let avg = times.reduce(0, +) / Double(times.count)
        let best = times.min() ?? 0
        let worst = times.max() ?? 0

        let goal: TimeInterval = 10800
        var streak = 0
        let sorted = history.sorted { $0.date > $1.date }
        for record in sorted {
            guard record.totalSeconds > 0 else { continue }
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
