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
    private static let hasAuthorizedKey = "tuff_hasAuthorizedScreenTime"
    @Published var selectedAppsToBlock: FamilyActivitySelection = FamilyActivitySelection() {
        didSet { persistSelection() }
    }
    @Published var appsToTrack: FamilyActivitySelection = FamilyActivitySelection(includeEntireCategory: true) {
        didSet { persistTrackSelection() }
    }
    @Published var isMonitoring = false
    @Published var todayMinutes: Int = 0
    @Published var estimatedTodayMinutes: Int = 0
    @Published var blockTimerEndDate: Date? = nil
    @Published var isActivelyBlocking: Bool = false

    var hasTrackingSelection: Bool {
        !appsToTrack.applicationTokens.isEmpty
            || !appsToTrack.categoryTokens.isEmpty
            || !appsToTrack.webDomainTokens.isEmpty
    }

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
    private static let monitoringRegistrationKey = "savedMonitoringRegistrationSignature"
    private init() {
        store = ManagedSettingsStore()
        center = DeviceActivityCenter()

        let liveStatus = AuthorizationCenter.shared.authorizationStatus == .approved
        let persisted = UserDefaults.standard.bool(forKey: Self.hasAuthorizedKey)
        isAuthorized = liveStatus || persisted

        if let data = UserDefaults.standard.data(forKey: Self.selectionKey),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selectedAppsToBlock = selection
        }

        if let data = UserDefaults.standard.data(forKey: Self.trackSelectionKey),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            appsToTrack = selection
        }
        authObserver = AuthorizationCenter.shared
            .objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let self else { return }
                    let status = AuthorizationCenter.shared.authorizationStatus == .approved
                    if status {
                        UserDefaults.standard.set(true, forKey: Self.hasAuthorizedKey)
                    }
                    self.isAuthorized = status || UserDefaults.standard.bool(forKey: Self.hasAuthorizedKey)
                }
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
        }
    }

    /// Call this when the app becomes active so the status is always fresh.
    func recheckAuthorization() {
        let live = AuthorizationCenter.shared.authorizationStatus == .approved
        if live { UserDefaults.standard.set(true, forKey: Self.hasAuthorizedKey) }
        isAuthorized = live || UserDefaults.standard.bool(forKey: Self.hasAuthorizedKey)
        refreshTodayMinutes()
        refreshEstimatedMinutes()
        // Break expired while backgrounded — re-lock
        if let end = blockTimerEndDate, Date() >= end {
            blockTimerTask?.cancel()
            blockTimerTask = nil
            blockTimerEndDate = nil
            blockSelectedApps()
        }
    }

    // MARK: - Break Timer (apps are always locked; a break temporarily unblocks them)

    /// Always re-apply the shield unless a break is currently active.
    func applyAlwaysOnBlocking() {
        guard isAuthorized else { return }
        let hasApps = !selectedAppsToBlock.applicationTokens.isEmpty
            || !selectedAppsToBlock.categoryTokens.isEmpty
        guard hasApps else { return }
        guard blockTimerEndDate == nil else { return }
        blockSelectedApps()
    }

    /// Start a break: unblock apps for `duration`, then automatically re-lock.
    func startBlockTimer(duration: TimeInterval) {
        blockTimerTask?.cancel()
        blockTimerTask = nil

        let end = Date().addingTimeInterval(duration)
        blockTimerEndDate = end

        // Unblock apps for the break duration
        store?.clearAllSettings()
        isActivelyBlocking = false

        blockTimerTask = Task {
            let delay = end.timeIntervalSince(Date())
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.blockTimerEndDate = nil
                self.blockSelectedApps()  // Re-lock when break ends
            }
        }
        startLiveActivity(endDate: end)
    }

    /// End the break early and immediately re-lock.
    func cancelBlockTimer() {
        blockTimerTask?.cancel()
        blockTimerTask = nil
        blockTimerEndDate = nil
        endLiveActivity()
        blockSelectedApps()
    }

    /// Purchase a break: unblock for `minutes`, then atomically increment each active league's
    /// ledger entry for this user using FieldValue.increment (no transaction needed).
    func buyBreak(minutes: Int, uid: String, leagues: [League]) async {
        startBlockTimer(duration: TimeInterval(minutes * 60))

        let activeLeagues = leagues.filter { $0.isActive }
        guard !activeLeagues.isEmpty else {
            print("[Tuff] buyBreak: no active leagues to charge")
            return
        }

        let db = Firestore.firestore()

        await withTaskGroup(of: Void.self) { group in
            for league in activeLeagues {
                let costCents = max(1, Int(round(Double(minutes) / 60.0 * Double(league.pricePerHourCents))))
                let docRef = db.collection("leagues").document(league.id)
                let leagueId = league.id

                group.addTask {
                    do {
                        // ledger.{uid}.boughtCents / boughtMinutes are top-level map fields —
                        // FieldValue.increment is atomic and needs no transaction.
                        try await docRef.updateData([
                            "ledger.\(uid).boughtCents":   FieldValue.increment(Int64(costCents)),
                            "ledger.\(uid).boughtMinutes": FieldValue.increment(Int64(minutes))
                        ])
                        print("[Tuff] buyBreak: +\(costCents)¢ / +\(minutes)m → league \(leagueId)")
                    } catch {
                        print("[Tuff] buyBreak: FAILED for league \(leagueId): \(error.localizedDescription)")
                    }
                }
            }
        }
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
            UserDefaults.standard.set(true, forKey: Self.hasAuthorizedKey)
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
        } else {
            todayMinutes = 0
        }
    }

    func refreshEstimatedMinutes() {
        estimatedTodayMinutes = Self.readEstimatedMinutesFromLog()
    }

    @Published var monitoringDebug: String = ""
    @Published var isRegisteringMonitoring = false

    /// Registers 24 one-hour schedules. The current hour is registered first
    /// so tracking can begin quickly, then the remaining hours are registered
    /// concurrently in the background. Each hour uses 1-minute thresholds 1...59.
    /// No includesPastActivity. Extension logs to a file, not UserDefaults.
    func startMonitoring(force: Bool = false) {
        refreshEstimatedMinutes()
        if isRegisteringMonitoring {
            monitoringDebug = "registering..."
            return
        }
        guard isAuthorized else {
            monitoringDebug = "not authorized"
            return
        }
        guard let center else {
            monitoringDebug = "center is nil"
            return
        }

        let appTokens = appsToTrack.applicationTokens
        let catTokens = appsToTrack.categoryTokens
        let webTokens = appsToTrack.webDomainTokens

        guard !appTokens.isEmpty || !catTokens.isEmpty || !webTokens.isEmpty else {
            monitoringDebug = "no apps/categories selected — open picker first"
            return
        }

        let signature = monitoringSignature(
            applications: appTokens.count,
            categories: catTokens.count,
            webDomains: webTokens.count
        )
        let savedSignature = UserDefaults.standard.string(forKey: Self.monitoringRegistrationKey)
        if !force, savedSignature == signature {
            isMonitoring = true
            monitoringDebug = "already registered: 24 schedules, 59 events, \(appTokens.count) apps, \(catTokens.count) cats"
            return
        }

        isRegisteringMonitoring = true
        monitoringDebug = "registering..."

        let intervals = Self.generateHourlyIntervals()
        let activeIntervalIndex = Self.currentIntervalIndex()

        // Capture everything we need as local values so the background task
        // doesn't need to touch self at all.
        let capturedAppTokens = appTokens
        let capturedCatTokens = catTokens
        let capturedWebTokens = webTokens

        Task.detached(priority: .userInitiated) {
            let bgCenter = DeviceActivityCenter()
            bgCenter.stopMonitoring()

            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            for minute in 1...59 {
                let eventName = DeviceActivityEvent.Name("tuff.\(minute).threshold")
                events[eventName] = DeviceActivityEvent(
                    applications: capturedAppTokens,
                    categories: capturedCatTokens,
                    webDomains: capturedWebTokens,
                    threshold: DateComponents(minute: minute)
                )
            }

            var registeredCount = 0
            var errors: [String] = []

            func registerInterval(_ index: Int) -> String? {
                let (startTime, endTime) = intervals[index]
                let schedule = DeviceActivitySchedule(
                    intervalStart: startTime,
                    intervalEnd: endTime,
                    repeats: true
                )
                let activity = DeviceActivityName("tuff.schedule.\(index)")
                do {
                    let center = DeviceActivityCenter()
                    try center.startMonitoring(activity, during: schedule, events: events)
                    return nil
                } catch {
                    return "s\(index): \(error.localizedDescription)"
                }
            }

            // Phase 1: register the currently active 1-hour window first so tracking
            // can begin for "right now" before the full daily setup finishes.
            if let error = registerInterval(activeIntervalIndex) {
                errors.append(error)
            } else {
                registeredCount += 1
            }

            await MainActor.run {
                let hasActiveWindow = registeredCount > 0
                ScreenTimeManager.shared.isMonitoring = hasActiveWindow
                if hasActiveWindow {
                    ScreenTimeManager.shared.monitoringDebug = "live now: 1/24 schedules, finishing setup..."
                } else {
                    ScreenTimeManager.shared.monitoringDebug = "registering active window failed, finishing setup..."
                }
            }

            // Phase 2: register the remaining 23 windows concurrently in the background.
            await withTaskGroup(of: (Int, String?).self) { group in
                for index in intervals.indices where index != activeIntervalIndex {
                    group.addTask {
                        (index, registerInterval(index))
                    }
                }

                for await (_, error) in group {
                    if let error {
                        errors.append(error)
                    } else {
                        registeredCount += 1
                    }

                    let progress = registeredCount
                    await MainActor.run {
                        if progress < intervals.count {
                            ScreenTimeManager.shared.monitoringDebug = "live now: \(progress)/24 schedules, finishing setup..."
                        }
                    }
                }
            }

            let resultDebug: String
            if errors.isEmpty {
                resultDebug = "OK: \(registeredCount)/24, \(events.count) events, \(capturedAppTokens.count) apps, \(capturedCatTokens.count) cats"
            } else {
                resultDebug = "\(registeredCount)/24 OK, errors: \(errors.joined(separator: "; "))"
            }
            let resultMonitoring = registeredCount > 0

            await MainActor.run {
                ScreenTimeManager.shared.isMonitoring = resultMonitoring
                ScreenTimeManager.shared.monitoringDebug = resultDebug
                ScreenTimeManager.shared.isRegisteringMonitoring = false
                if resultMonitoring {
                    UserDefaults.standard.set(signature, forKey: Self.monitoringRegistrationKey)
                }
            }
        }
    }

    private func monitoringSignature(applications: Int, categories: Int, webDomains: Int) -> String {
        let data = (try? JSONEncoder().encode(appsToTrack)) ?? Data()
        let hash = Self.fnv1a64Hex(data)
        return "v2-hourly59-\(applications)-\(categories)-\(webDomains)-\(hash)"
    }

    private static func fnv1a64Hex(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    /// Calendar-based interval generation for 24 one-hour windows.
    private static func generateHourlyIntervals() -> [(DateComponents, DateComponents)] {
        let calendar = Calendar.current
        let base = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: Date())!

        var intervals: [(DateComponents, DateComponents)] = []
        for hour in 0...23 {
            let startDate = calendar.date(byAdding: .hour, value: hour, to: base)!
            let endDate = calendar.date(byAdding: .hour, value: 1, to: startDate)!.addingTimeInterval(-1)
            let start = calendar.dateComponents([.hour, .minute, .second], from: startDate)
            let end = calendar.dateComponents([.hour, .minute, .second], from: endDate)
            intervals.append((start, end))
        }
        return intervals
    }

    private static func currentIntervalIndex(now: Date = Date()) -> Int {
        let hour = Calendar.current.component(.hour, from: now)
        return max(0, min(23, hour))
    }

    // MARK: - File-based log reader (avoids UserDefaults crash in extension)

    private static var monitorLogURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.collinboler.tuff")?
            .appendingPathComponent("monitor_log.txt")
    }

    /// Reads today's threshold fires from the file log written by the extension.
    static func readEstimatedMinutesFromLog() -> Int {
        guard let url = monitorLogURL,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return 0 }

        let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        var totalMinutes = 0

        for line in content.split(separator: "\n") {
            let parts = line.split(separator: ",")
            guard parts.count >= 3,
                  let ts = Double(parts[0]),
                  ts >= todayStart,
                  parts[1] == "threshold",
                  let mins = Int(parts[2]) else { continue }
            totalMinutes += mins
        }
        return totalMinutes
    }

    static func clearMonitorLog() {
        guard let url = monitorLogURL else { return }
        try? Data().write(to: url, options: .atomic)
    }

    /// Returns all log lines for debugging
    static func readMonitorLog() -> String {
        guard let url = monitorLogURL,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return "(no log file)" }
        let lines = content.split(separator: "\n")
        if lines.isEmpty { return "(log empty)" }
        let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let todayLines = lines.filter {
            guard let ts = Double($0.split(separator: ",").first ?? "") else { return false }
            return ts >= todayStart
        }
        let total = todayLines.count
        let thresholds = todayLines.filter { $0.contains("threshold") }.count
        let starts = todayLines.filter { $0.contains(",start,") }.count
        let ends = todayLines.filter { $0.contains(",end,") }.count
        var summary = "\(total) events today (starts: \(starts), ends: \(ends), thresholds: \(thresholds))"
        let estimatedMinutes = todayLines.reduce(into: 0) { partialResult, line in
            let parts = line.split(separator: ",")
            guard parts.count >= 3,
                  parts[1] == "threshold",
                  let mins = Int(parts[2]) else { return }
            partialResult += mins
        }
        summary += "\nestimated: \(estimatedMinutes)m"
        if let lastLine = todayLines.last {
            let parts = lastLine.split(separator: ",")
            if let ts = Double(parts.first ?? "") {
                let age = Int(Date().timeIntervalSince1970 - ts)
                summary += "\nlast event: \(age)s ago"
            }
        }
        // Show last 5 raw lines
        let tail = todayLines.suffix(5)
        if !tail.isEmpty {
            summary += "\n---\n" + tail.joined(separator: "\n")
        }
        return summary
    }

    func stopMonitoring() {
        guard let center else { return }
        center.stopMonitoring()
        isMonitoring = false
        UserDefaults.standard.removeObject(forKey: Self.monitoringRegistrationKey)
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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Use file-based estimated minutes from the monitor extension
        let estMinutes = Self.readEstimatedMinutesFromLog()
        let estSeconds = TimeInterval(estMinutes * 60)

        if estSeconds > 0 {
            var history = TuffSharedStore.dailyHistory()
            history.removeAll { calendar.isDate($0.date, inSameDayAs: today) }
            let record = DailyRecord(id: UUID(), date: today, totalSeconds: estSeconds, appBreakdown: [])
            history.append(record)
            let sorted = history.sorted { $0.date > $1.date }
            TuffSharedStore.saveDailyHistory(Array(sorted.prefix(30)))
        }

        self.doSync(uid: uid)
    }

    private func doSync(uid: String) {
        let history = TuffSharedStore.dailyHistory().sorted(by: { $0.date > $1.date })
        let estMinutes = Self.readEstimatedMinutesFromLog()
        self.estimatedTodayMinutes = estMinutes

        let todayMinutes = estMinutes > 0 ? estMinutes : (history.first.map { Int($0.totalSeconds / 60) } ?? 0)
        self.todayMinutes = todayMinutes

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

        let liveApps = TuffSharedStore.appBreakdown()
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
                "estimatedScreenTimeMinutes": estMinutes,
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
