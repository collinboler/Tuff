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

    private var store: ManagedSettingsStore?
    private var center: DeviceActivityCenter?

    private init() {
        // These will fail gracefully without the Family Controls entitlement
        store = try? ManagedSettingsStore()
        center = DeviceActivityCenter()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
            print("Screen Time authorized")
        } catch {
            print("Screen Time authorization unavailable (needs Family Controls entitlement): \(error.localizedDescription)")
            isAuthorized = false
        }
    }

    // MARK: - App Blocking (Friend 2FA / Custom Challenge)

    func blockSelectedApps() {
        guard isAuthorized, let store else { return }

        store.shield.applications = selectedAppsToBlock.applicationTokens.isEmpty
            ? nil
            : selectedAppsToBlock.applicationTokens
        store.shield.applicationCategories = selectedAppsToBlock.categoryTokens.isEmpty
            ? nil
            : ShieldSettings.ActivityCategoryPolicy.specific(selectedAppsToBlock.categoryTokens)
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
        } catch {
            print("Failed to start monitoring: \(error.localizedDescription)")
        }
    }

    func stopMonitoring() {
        let activityName = DeviceActivityName(rawValue: "dailyActivity")
        center?.stopMonitoring([activityName])
        isMonitoring = false
    }

    // MARK: - Screen Time Data (sample data until entitlement is approved)

    func fetchTodayScreenTime() -> TimeInterval {
        return 9420 // 2h 37m
    }

    func fetchWeeklyData() -> [DailyScreenTime] {
        return DailyScreenTime.sampleWeek
    }

    func fetchMonthlyData() -> [DailyScreenTime] {
        return DailyScreenTime.sampleMonth
    }

    func fetchStats() -> ScreenTimeStats {
        return DailyScreenTime.sampleStats
    }
}
