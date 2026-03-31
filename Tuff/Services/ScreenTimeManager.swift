import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings
import Combine
import ActivityKit
import FirebaseFirestore

// BlockTimerAttributes is defined in BlockTimerAttributes.swift (compiled in both
// the main Tuff target and the TuffLiveActivity widget extension target).

@MainActor
class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()

    @Published var isAuthorized = false
    @Published var blockTimerEndDate: Date? = nil
    @Published var breakStartDate: Date? = nil    // persisted so refund calc survives restarts
    @Published var isActivelyBlocking: Bool = false
    @Published var liveActivitiesEnabled: Bool = true

    private var blockTimerTask: Task<Void, Never>?
    private var liveActivity: Activity<BlockTimerAttributes>?
    private var store: ManagedSettingsStore?
    private var authObserver: AnyCancellable?

    private static let hasAuthorizedKey = "tuff_hasAuthorizedScreenTime"
    // Shared with the TuffDeviceActivity extension so it can check break state
    static let sharedDefaults = UserDefaults(suiteName: "group.com.collinboler.tuff")
    static let breakEndDateKey   = "tuff_breakEndDate"
    static let breakStartDateKey = "tuff_breakStartDate"

    private init() {
        store = ManagedSettingsStore()

        let liveStatus = AuthorizationCenter.shared.authorizationStatus == .approved
        let persisted = UserDefaults.standard.bool(forKey: Self.hasAuthorizedKey)
        isAuthorized = liveStatus || persisted

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

        // Restore break timer that may have been active when the app was killed.
        if let savedEnd = Self.sharedDefaults?.object(forKey: Self.breakEndDateKey) as? Date {
            if Date() < savedEnd {
                blockTimerEndDate = savedEnd
                breakStartDate = Self.sharedDefaults?.object(forKey: Self.breakStartDateKey) as? Date
                scheduleRelock(endDate: savedEnd)
            } else {
                Self.sharedDefaults?.removeObject(forKey: Self.breakEndDateKey)
                Self.sharedDefaults?.removeObject(forKey: Self.breakStartDateKey)
            }
        }

        liveActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Call this when the app becomes active so the status is always fresh.
    func recheckAuthorization() {
        let live = AuthorizationCenter.shared.authorizationStatus == .approved
        if live { UserDefaults.standard.set(true, forKey: Self.hasAuthorizedKey) }
        isAuthorized = live || UserDefaults.standard.bool(forKey: Self.hasAuthorizedKey)
        // Break expired while backgrounded — re-lock
        if let end = blockTimerEndDate, Date() >= end {
            blockTimerTask?.cancel()
            blockTimerTask = nil
            blockTimerEndDate = nil
            blockSelectedApps()
        }
        // Sweep any orphaned Live Activities from previous sessions
        sweepStaleLiveActivities()
    }

    /// Clean up any orphaned Live Activities from previous sessions.
    /// Only ends ones that are truly stale (break expired). The current
    /// activity is left running — it will be updated to locked state.
    private func sweepStaleLiveActivities() {
        let currentId = liveActivity?.id
        Task {
            for activity in Activity<BlockTimerAttributes>.activities {
                if activity.id == currentId { continue }
                // Only end orphans whose break has already expired
                if activity.content.state.isOnBreak,
                   Date() >= activity.content.state.endDate {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    // MARK: - Break Timer (apps are always locked; a break temporarily unblocks them)

    /// Always re-apply the shield unless a break is currently active.
    func applyAlwaysOnBlocking() {
        guard isAuthorized else { return }
        guard blockTimerEndDate == nil else { return }
        blockSelectedApps()
    }

    /// Start a break: unblock apps for `duration`, then automatically re-lock.
    func startBlockTimer(duration: TimeInterval) {
        blockTimerTask?.cancel()
        blockTimerTask = nil

        let start = Date()
        let end = start.addingTimeInterval(duration)
        blockTimerEndDate = end
        breakStartDate = start
        Self.sharedDefaults?.set(end,   forKey: Self.breakEndDateKey)
        Self.sharedDefaults?.set(start, forKey: Self.breakStartDateKey)

        // Unblock apps for the break duration and re-enable app removal
        store?.clearAllSettings()
        store?.application.denyAppRemoval = false
        isActivelyBlocking = false

        scheduleRelock(endDate: end)
        updateLiveActivityForBreak(endDate: end)
    }

    /// Shared relock scheduling — used by startBlockTimer and break restoration on init.
    private func scheduleRelock(endDate: Date) {
        blockTimerTask?.cancel()
        blockTimerTask = Task {
            let delay = endDate.timeIntervalSince(Date())
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.blockTimerEndDate = nil
                self.breakStartDate = nil
                Self.sharedDefaults?.removeObject(forKey: Self.breakEndDateKey)
                Self.sharedDefaults?.removeObject(forKey: Self.breakStartDateKey)
                self.blockSelectedApps()
                self.ensureLockedLiveActivity()
            }
        }
    }

    /// End the break early, re-lock immediately, and refund the unused time.
    ///
    /// Charging rule — only FULL minutes actually used are kept:
    ///   • Used 1m 30s → charge 1 min  (floor of seconds used / 60)
    ///   • Used 0m 30s → charge 0 min  (full refund)
    ///
    /// This means `refundMinutes = originalMinutes - floor(secondsUsed / 60)`.
    /// Returns the number of minutes refunded (0 if none).
    @discardableResult
    func cancelBreakEarly(uid: String, leagues: [League]) async -> Int {
        let endDate   = blockTimerEndDate
        let startDate = breakStartDate ?? Self.sharedDefaults?.object(forKey: Self.breakStartDateKey) as? Date

        // Re-lock immediately
        blockTimerTask?.cancel()
        blockTimerTask = nil
        blockTimerEndDate = nil
        breakStartDate = nil
        Self.sharedDefaults?.removeObject(forKey: Self.breakEndDateKey)
        Self.sharedDefaults?.removeObject(forKey: Self.breakStartDateKey)
        blockSelectedApps()
        ensureLockedLiveActivity()

        guard let endDate, let startDate else { return 0 }

        let secondsUsed = max(0, Date().timeIntervalSince(startDate))

        // If less than 1 full minute was used, keep the full charge — no refund.
        // This prevents gaming (buy break, cancel immediately for free).
        guard secondsUsed >= 60 else {
            print("[Tuff] earlyEnd: used \(Int(secondsUsed))s < 60 — no refund")
            return 0
        }

        let originalMinutes = Int((endDate.timeIntervalSince(startDate) / 60).rounded())
        let minutesKept     = Int(secondsUsed / 60)          // floor
        let refundMinutes   = max(0, originalMinutes - minutesKept)

        print("[Tuff] earlyEnd: used \(Int(secondsUsed))s → kept \(minutesKept)m / refund \(refundMinutes)m of \(originalMinutes)m")
        guard refundMinutes > 0 else { return 0 }

        let activeLeagues = leagues.filter { $0.isActive }
        guard !activeLeagues.isEmpty else { return refundMinutes }

        let db = Firestore.firestore()
        await withTaskGroup(of: Void.self) { group in
            for league in activeLeagues {
                let refundCents = max(0, Int(round(Double(refundMinutes) / 60.0 * Double(league.pricePerHourCents))))
                guard refundCents > 0 else { continue }
                let docRef = db.collection("leagues").document(league.id)
                let lid = league.id
                group.addTask {
                    do {
                        try await docRef.updateData([
                            "ledger.\(uid).boughtCents":   FieldValue.increment(-Int64(refundCents)),
                            "ledger.\(uid).boughtMinutes": FieldValue.increment(-Int64(refundMinutes))
                        ])
                        print("[Tuff] earlyEnd: -\(refundCents)¢ / -\(refundMinutes)m refund → league \(lid)")
                    } catch {
                        print("[Tuff] earlyEnd: refund FAILED for league \(lid): \(error.localizedDescription)")
                    }
                }
            }
        }
        return refundMinutes
    }

    /// Re-lock without any refund (used when no leagues are active or break expired naturally).
    func cancelBlockTimer() {
        blockTimerTask?.cancel()
        blockTimerTask = nil
        blockTimerEndDate = nil
        breakStartDate = nil
        Self.sharedDefaults?.removeObject(forKey: Self.breakEndDateKey)
        Self.sharedDefaults?.removeObject(forKey: Self.breakStartDateKey)
        blockSelectedApps()
        ensureLockedLiveActivity()
    }

    /// Register 24 hourly DeviceActivity schedules (no events — just for the
    /// intervalDidStart callback that re-applies shields when the app is killed).
    func registerBlockingSchedules() {
        guard isAuthorized else { return }
        let center = DeviceActivityCenter()
        let calendar = Calendar.current
        let base = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: Date())!
        for hour in 0...23 {
            let startDate = calendar.date(byAdding: .hour, value: hour, to: base)!
            let endDate = calendar.date(byAdding: .hour, value: 1, to: startDate)!.addingTimeInterval(-1)
            let start = calendar.dateComponents([.hour, .minute, .second], from: startDate)
            let end = calendar.dateComponents([.hour, .minute, .second], from: endDate)
            let schedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: true)
            try? center.startMonitoring(DeviceActivityName("tuff.block.\(hour)"), during: schedule)
        }
        print("[Tuff] Registered 24 hourly blocking schedules")
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
    // The Live Activity runs continuously while blocking is active:
    //   • Locked state  → T logo + lock icon (no break)
    //   • Break state   → T logo + countdown timer
    // We update the content state rather than ending/restarting to avoid flicker.

    /// Ensure a Live Activity exists and is showing the "locked" state.
    func ensureLockedLiveActivity() {
        liveActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        guard liveActivitiesEnabled else { return }

        let lockedState = BlockTimerAttributes.ContentState(
            isOnBreak: false,
            endDate: Date.distantFuture,
            appCount: 0
        )

        if let existing = liveActivity {
            // Update existing activity to locked state
            Task {
                await existing.update(ActivityContent(state: lockedState, staleDate: nil))
            }
        } else {
            // No activity running — start one
            requestFreshActivity(state: lockedState)
        }
    }

    /// Switch the Live Activity to break mode with a countdown.
    private func updateLiveActivityForBreak(endDate: Date) {
        liveActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        guard liveActivitiesEnabled else { return }

        let breakState = BlockTimerAttributes.ContentState(
            isOnBreak: true,
            endDate: endDate,
            appCount: 0
        )

        if let existing = liveActivity {
            Task {
                await existing.update(ActivityContent(state: breakState, staleDate: endDate))
            }
        } else {
            requestFreshActivity(state: breakState)
        }
    }

    private func requestFreshActivity(state: BlockTimerAttributes.ContentState) {
        let previousActivity = liveActivity
        liveActivity = nil
        let stale: Date? = state.isOnBreak ? state.endDate : nil
        let content = ActivityContent(state: state, staleDate: stale)
        do {
            liveActivity = try Activity.request(
                attributes: BlockTimerAttributes(appCount: 0),
                content: content,
                pushType: nil
            )
            print("[Tuff] Live Activity started: \(liveActivity?.id ?? "?")")
        } catch {
            print("[Tuff] Live Activity failed: \(error.localizedDescription)")
        }
        let newId = liveActivity?.id
        Task {
            await previousActivity?.end(nil, dismissalPolicy: .immediate)
            for activity in Activity<BlockTimerAttributes>.activities where activity.id != newId {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func endLiveActivity() {
        let toEnd = liveActivity
        liveActivity = nil
        Task {
            await toEnd?.end(nil, dismissalPolicy: .immediate)
            for activity in Activity<BlockTimerAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
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
            registerBlockingSchedules()
            print("[Tuff] Screen Time authorized ✓")
        } catch {
            print("[Tuff] Screen Time auth failed: \(error)")
            isAuthorized = false
        }
    }

    // MARK: - App Blocking

    /// Blocks all app categories and web domains automatically — no manual token selection needed.
    /// The league defines the blocking policy; the default is to block everything non-essential.
    func blockSelectedApps() {
        guard let store else {
            print("[Tuff] blockSelectedApps: store is nil")
            return
        }
        store.shield.applicationCategories = .all()
        store.shield.webDomainCategories = .all()
        store.application.denyAppRemoval = true
        isActivelyBlocking = true
        print("[Tuff] Shield applied — all app categories and web domains blocked")
        ensureLockedLiveActivity()
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

}
