import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings
import Combine
import ActivityKit
import FirebaseFirestore
import FirebaseAuth

// BlockTimerAttributes is defined in BlockTimerAttributes.swift (compiled in both
// the main Tuff target and the TuffLiveActivity widget extension target).

@MainActor
class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()

    @Published var isAuthorized = false
    @Published var selectedAppsToBlock: FamilyActivitySelection = FamilyActivitySelection() {
        didSet { persistSelection() }
    }
    @Published var appsToTrack: FamilyActivitySelection = FamilyActivitySelection() {
        didSet { persistTrackSelection() }
    }
    @Published var isMonitoring = false
    @Published var todayMinutes: Int = 0
    @Published var blockTimerEndDate: Date? = nil
    @Published var isActivelyBlocking: Bool = false

    private var blockTimerTask: Task<Void, Never>?
    private var liveActivity: Activity<BlockTimerAttributes>?

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
    private var authObserver: AnyCancellable?

    private static let selectionKey = "savedFamilyActivitySelection"
    private static let trackSelectionKey = "savedTrackActivitySelection"
    private static let sharedTrackSelectionKey = "trackingFamilyActivitySelection"

    private init() {
        store = ManagedSettingsStore()
        center = DeviceActivityCenter()
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved

        if let data = UserDefaults.standard.data(forKey: Self.selectionKey),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selectedAppsToBlock = selection
        }

        if let data = UserDefaults.standard.data(forKey: Self.trackSelectionKey),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            appsToTrack = selection
        }
        persistTrackSelection()

        authObserver = AuthorizationCenter.shared
            .objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            }
    }

    private func persistSelection() {
        if let data = try? JSONEncoder().encode(selectedAppsToBlock) {
            UserDefaults.standard.set(data, forKey: Self.selectionKey)
        }
    }

    private func persistTrackSelection() {
        if let data = try? JSONEncoder().encode(appsToTrack) {
            UserDefaults.standard.set(data, forKey: Self.trackSelectionKey)
            TuffSharedStore.defaults?.set(data, forKey: Self.sharedTrackSelectionKey)
            TuffSharedStore.defaults?.synchronize()
        }
    }

    /// Call this when the app becomes active so the status is always fresh.
    func recheckAuthorization() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        refreshTodayMinutes()
        // Auto-unblock if timer expired while app was backgrounded
        if let end = blockTimerEndDate, Date() >= end {
            blockTimerTask?.cancel()
            blockTimerTask = nil
            blockTimerEndDate = nil
            unblockAllApps()
        }
    }

    // MARK: - Block Timer

    func startBlockTimer(duration: TimeInterval) {
        // Cancel any previous timer cleanly first
        blockTimerTask?.cancel()
        blockTimerTask = nil

        let end = Date().addingTimeInterval(duration)
        blockTimerEndDate = end
        // Caller is responsible for calling blockSelectedApps() before this

        blockTimerTask = Task {
            let delay = end.timeIntervalSince(Date())
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.blockTimerEndDate = nil
                self.unblockAllApps()
            }
        }
        startLiveActivity(endDate: end)
    }

    func cancelBlockTimer() {
        blockTimerTask?.cancel()
        blockTimerTask = nil
        blockTimerEndDate = nil
        unblockAllApps()
    }

    // MARK: - Live Activity

    private func startLiveActivity(endDate: Date) {
        let info = ActivityAuthorizationInfo()
        guard info.areActivitiesEnabled else {
            print("[Tuff] Live Activities disabled by system")
            return
        }
        endLiveActivity()
        let appCount = selectedAppsToBlock.applicationTokens.count
            + selectedAppsToBlock.categoryTokens.count
        let attrs = BlockTimerAttributes(appCount: appCount)
        let state = BlockTimerAttributes.ContentState(endDate: endDate, appCount: appCount)
        let content = ActivityContent(state: state, staleDate: endDate.addingTimeInterval(60))
        do {
            liveActivity = try Activity.request(attributes: attrs, content: content, pushType: nil)
            print("[Tuff] Live Activity started: \(liveActivity?.id ?? "?")")
        } catch {
            print("[Tuff] Live Activity failed: \(error)")
        }
    }

    private func endLiveActivity() {
        guard let activity = liveActivity else { return }
        liveActivity = nil
        Task {
            let noContent: ActivityContent<BlockTimerAttributes.ContentState>? = nil
            await activity.end(noContent, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
        }
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
        store.shield.webDomainCategories = .all()
        isActivelyBlocking = true

        print("[Tuff] Shield applied — apps: \(store.shield.applications?.count ?? 0), categories: \(store.shield.applicationCategories != nil), webDomains: all")
    }

    func unblockAllApps() {
        store?.clearAllSettings()
        store?.shield.webDomainCategories = nil
        isActivelyBlocking = false
        endLiveActivity()
        print("[Tuff] All shields cleared")
    }


    func unblockWithFriend2FA(code: String, expectedCode: String) -> Bool {
        guard code == expectedCode else { return false }
        unblockAllApps()
        return true
    }

    // MARK: - Activity Monitoring

    func refreshTodayMinutes() {
        if let seconds = TuffSharedStore.todayScreenTime() {
            todayMinutes = Int(seconds) / 60
        }
    }

    /// Last monitoring start result for debug display
    @Published var monitoringDebug: String = ""

    /// Tokens used for monitoring: prefer `appsToTrack`, fall back to `selectedAppsToBlock`.
    var trackingTokens: (
        apps: Set<ApplicationToken>,
        cats: Set<ActivityCategoryToken>,
        webs: Set<WebDomainToken>
    ) {
        let trackApps = appsToTrack.applicationTokens
        let trackCats = appsToTrack.categoryTokens
        let trackWebs = appsToTrack.webDomainTokens
        if !trackApps.isEmpty || !trackCats.isEmpty || !trackWebs.isEmpty {
            return (trackApps, trackCats, trackWebs)
        }
        return (
            selectedAppsToBlock.applicationTokens,
            selectedAppsToBlock.categoryTokens,
            selectedAppsToBlock.webDomainTokens
        )
    }

    private func nextThresholdMinutes(from currentSeconds: TimeInterval) -> Int {
        let currentMinutes = max(0, Int(currentSeconds / 60))
        if currentMinutes < 10 {
            return currentMinutes + 1
        }
        return ((currentMinutes / 5) + 1) * 5
    }

    func startMonitoring() {
        refreshTodayMinutes()
        guard isAuthorized else {
            monitoringDebug = "not authorized"
            return
        }
        guard let center else {
            monitoringDebug = "center is nil"
            return
        }

        let (appTokens, catTokens, webTokens) = trackingTokens

        center.stopMonitoring()

        let activityName = DeviceActivityName(rawValue: "dailyActivity")

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        guard !appTokens.isEmpty || !catTokens.isEmpty || !webTokens.isEmpty else {
            monitoringDebug = "no apps selected — pick apps to track"
            try? center.startMonitoring(activityName, during: schedule)
            isMonitoring = true
            return
        }

        let nextThreshold = nextThresholdMinutes(from: TuffSharedStore.todayScreenTime() ?? 0)
        let eventName = DeviceActivityEvent.Name("screentime_\(nextThreshold)")

        func makeEvent(minutes: Int) -> DeviceActivityEvent {
            if #available(iOS 17.4, *) {
                return DeviceActivityEvent(
                    applications: appTokens,
                    categories: catTokens,
                    webDomains: webTokens,
                    threshold: DateComponents(minute: minutes),
                    includesPastActivity: true
                )
            } else {
                return DeviceActivityEvent(
                    applications: appTokens,
                    categories: catTokens,
                    webDomains: webTokens,
                    threshold: DateComponents(minute: minutes)
                )
            }
        }
        let events = [eventName: makeEvent(minutes: nextThreshold)]

        do {
            try center.startMonitoring(activityName, during: schedule, events: events)
            isMonitoring = true
            monitoringDebug = "OK: next=\(nextThreshold)m, \(appTokens.count) apps, \(catTokens.count) cats, \(webTokens.count) webs"
        } catch {
            monitoringDebug = "FAILED: \(error.localizedDescription)"
        }
    }

    func stopMonitoring() {
        center?.stopMonitoring([DeviceActivityName(rawValue: "dailyActivity")])
        isMonitoring = false
    }

    // MARK: - Screen Time Data (reads from App Group, written by TuffActivityReport extension)

    func fetchWeeklyData() -> [DailyScreenTime] {
        let history = TuffSharedStore.dailyHistory()
        guard !history.isEmpty else { return DailyScreenTime.sampleWeek }
        let calendar = Calendar.current
        return (0..<7).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
            let dayStart = calendar.startOfDay(for: date)
            if let record = history.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
                let apps = record.appBreakdown.map {
                    AppUsage(appName: $0.displayName, bundleIdentifier: $0.bundleID,
                             seconds: $0.totalSeconds, category: .other)
                }
                return DailyScreenTime(date: record.date, totalSeconds: record.totalSeconds, appBreakdown: apps)
            }
            return DailyScreenTime(date: date, totalSeconds: 0, appBreakdown: [])
        }
    }

    func fetchMonthlyData() -> [DailyScreenTime] {
        let history = TuffSharedStore.dailyHistory()
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
        let history = TuffSharedStore.dailyHistory()
        guard !history.isEmpty else { return DailyScreenTime.sampleStats }
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -period, to: calendar.startOfDay(for: Date()))!
        let periodEntries = history.filter { $0.date >= cutoff && $0.totalSeconds > 0 }
        guard !periodEntries.isEmpty else { return DailyScreenTime.sampleStats }
        let times = periodEntries.map { $0.totalSeconds }
        let avg = times.reduce(0, +) / Double(times.count)
        let goal: TimeInterval = 10800
        var streak = 0
        for record in history.sorted(by: { $0.date > $1.date }) {
            guard record.totalSeconds > 0 else { continue }
            if record.totalSeconds < goal { streak += 1 } else { break }
        }
        return ScreenTimeStats(dailyAverage: avg, bestDay: times.min() ?? 0,
                               worstDay: times.max() ?? 0, currentStreak: streak, dailyGoal: goal)
    }

    // MARK: - Sync to Firestore

    func syncScreenTimeToFirestore(uid: String) {
        // Snapshot current screen time before syncing
        // (Report extension wrote todayScreenTime to shared file, now we snapshot it to history)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let seconds = TuffSharedStore.todayScreenTime(), seconds > 0 else {
            // No data to snapshot, just sync empty
            self.doSync(uid: uid)
            return
        }

        var history = TuffSharedStore.dailyHistory()
        let breakdown = TuffSharedStore.appBreakdown()

        // Remove old entry for today if exists, add fresh one
        history.removeAll { calendar.isDate($0.date, inSameDayAs: today) }
        let record = DailyRecord(id: UUID(), date: today, totalSeconds: seconds, appBreakdown: breakdown)
        history.append(record)

        let sorted = history.sorted { $0.date > $1.date }
        TuffSharedStore.saveDailyHistory(Array(sorted.prefix(30)))

        // Now sync
        self.doSync(uid: uid)
    }

    private func doSync(uid: String) {
        let history = TuffSharedStore.dailyHistory().sorted(by: { $0.date > $1.date })
        let todaySeconds = TuffSharedStore.todayScreenTime() ?? 0
        let liveApps = TuffSharedStore.appBreakdown()

        let todayMinutes: Int
        if todaySeconds > 0 {
            todayMinutes = Int(todaySeconds / 60)
            self.todayMinutes = todayMinutes
        } else {
            todayMinutes = history.first.map { Int($0.totalSeconds / 60) } ?? 0
        }

        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"

        let historyData: [[String: Any]] = Array(history.prefix(30)).map { record in
            let apps: [[String: Any]] = record.appBreakdown.map {
                ["name": $0.displayName, "bundleID": $0.bundleID,
                 "seconds": $0.totalSeconds, "minutes": Int($0.totalSeconds / 60)]
            }
            return ["date": dateFmt.string(from: record.date),
                    "minutes": Int(record.totalSeconds / 60),
                    "seconds": record.totalSeconds,
                    "apps": apps]
        }

        let liveAppsData: [[String: Any]] = liveApps.map {
            ["name": $0.displayName, "bundleID": $0.bundleID,
             "seconds": $0.totalSeconds, "minutes": Int($0.totalSeconds / 60)]
        }

        print("[ScreenTime] Syncing: \(todayMinutes)m today, \(historyData.count) days")

        Task {
            let db = Firestore.firestore()
            let now = Timestamp(date: Date())

            try? await db.collection("users").document(uid).setData([
                "screenTimeMinutes":  todayMinutes,
                "screenTimeHistory":  historyData,
                "appBreakdown":       liveAppsData,
                "lastSyncedAt":       now
            ], merge: true)

            let leaguesSnap = try? await db.collection("leagues")
                .whereField("memberUids", arrayContains: uid)
                .getDocuments()
            for doc in leaguesSnap?.documents ?? [] {
                var profiles = doc.data()["memberProfiles"] as? [[String: Any]] ?? []
                guard let idx = profiles.firstIndex(where: { $0["uid"] as? String == uid }) else { continue }
                profiles[idx]["screenTimeMinutes"] = todayMinutes
                try? await db.collection("leagues").document(doc.documentID)
                    .updateData(["memberProfiles": profiles])
            }

            print("[ScreenTime] Synced OK")
        }
    }
}
