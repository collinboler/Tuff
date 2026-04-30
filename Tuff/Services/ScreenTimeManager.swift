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
    @Published var allowedAppSelection: FamilyActivitySelection = FamilyActivitySelection()

    private var blockTimerTask: Task<Void, Never>?
    private var liveActivity: Activity<BlockTimerAttributes>?
    private var store: ManagedSettingsStore?
    private var authObserver: AnyCancellable?

    /// Foreground "heartbeat" that re-asserts the shield every 60 seconds.
    /// The OS-side ManagedSettings configuration is normally durable, but
    /// users have reported it occasionally getting cleared by iOS — re-writing
    /// the same config every minute while Tuff is open is cheap, idempotent,
    /// and closes that gap without waiting for the DeviceActivity extension's
    /// 1–2 hour interval boundary. Started by `startShieldHeartbeat()` from
    /// the `didBecomeActive` notification, stopped on background.
    private var shieldHeartbeat: Task<Void, Never>?

    private static let hasAuthorizedKey = "tuff_hasAuthorizedScreenTime"
    // Shared with the TuffDeviceActivity extension so it can check break state
    static let sharedDefaults = UserDefaults(suiteName: "group.com.collinboler.tuff")
    static let breakEndDateKey        = "tuff_breakEndDate"
    static let breakStartDateKey      = "tuff_breakStartDate"
    static let allowedSelectionKey    = "tuff_allowedAppSelection"

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

        // Restore saved allowed-app selection from the shared app group
        if let data = Self.sharedDefaults?.data(forKey: Self.allowedSelectionKey),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            allowedAppSelection = decoded
        }
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
            breakStartDate = nil
            Self.sharedDefaults?.removeObject(forKey: Self.breakEndDateKey)
            Self.sharedDefaults?.removeObject(forKey: Self.breakStartDateKey)
            DeviceActivityCenter().stopMonitoring([DeviceActivityName("tuff.breakEnd")])
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

    // MARK: - Allowed App Selection

    /// Persist a `FamilyActivitySelection` to the shared app group so both the main app
    /// and the TuffDeviceActivity extension apply the same exemptions when relocking.
    func saveAllowedSelection(_ selection: FamilyActivitySelection) {
        allowedAppSelection = selection
        guard let data = try? JSONEncoder().encode(selection) else { return }
        Self.sharedDefaults?.set(data, forKey: Self.allowedSelectionKey)
    }

    // MARK: - Break Timer (apps are always locked; a break temporarily unblocks them)

    /// Always re-apply the shield unless a break is currently active.
    func applyAlwaysOnBlocking() {
        guard isAuthorized else { return }
        guard blockTimerEndDate == nil else { return }
        blockSelectedApps()
    }

    /// Start the foreground heartbeat. Safe to call repeatedly (a no-op if
    /// already running). Cancelled on background or when the user buys a
    /// break (we don't want to clobber the active break window).
    func startShieldHeartbeat() {
        guard isAuthorized else { return }
        guard shieldHeartbeat == nil else { return }
        shieldHeartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    guard self.isAuthorized else { return }
                    guard self.blockTimerEndDate == nil else { return }
                    self.blockSelectedApps()
                }
            }
        }
    }

    /// Stop the foreground heartbeat. Called when the app backgrounds or
    /// when a break starts (so the heartbeat doesn't fight the unblock).
    func stopShieldHeartbeat() {
        shieldHeartbeat?.cancel()
        shieldHeartbeat = nil
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

        // Unblock apps for the break duration and re-enable app removal.
        // Stop the heartbeat so it doesn't immediately re-shield mid-break.
        stopShieldHeartbeat()
        store?.clearAllSettings()
        store?.application.denyAppRemoval = false
        isActivelyBlocking = false

        scheduleRelock(endDate: end)
        scheduleRelockViaExtension(endDate: end)
        updateLiveActivityForBreak(endDate: end)
    }

    /// Shared relock scheduling — used by startBlockTimer and break restoration on init.
    /// Uses Task.sleep for accuracy when the app is foregrounded, but the companion
    /// scheduleRelockViaExtension() handles the case where the app is suspended/killed.
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
                self.startShieldHeartbeat()
                // Cancel the one-shot extension schedule (it may not have fired yet)
                DeviceActivityCenter().stopMonitoring([DeviceActivityName("tuff.breakEnd")])
            }
        }
    }

    /// Register a one-shot DeviceActivitySchedule that fires shortly after the break ends.
    /// DeviceActivitySchedule only honours .hour and .minute (seconds are ignored), so we
    /// schedule the window to START 1 minute after the break end time — guaranteeing that
    /// when intervalDidStart fires the break will definitely be over and the extension's
    /// `Date() < breakEnd` guard won't incorrectly skip the relock.
    private func scheduleRelockViaExtension(endDate: Date) {
        let center = DeviceActivityCenter()
        center.stopMonitoring([DeviceActivityName("tuff.breakEnd")])

        let calendar = Calendar.current
        // Add 1 full minute so the schedule start is always AFTER the break finishes,
        // even accounting for the framework's second-level precision being dropped.
        let fireDate    = endDate.addingTimeInterval(60)
        let windowEnd   = fireDate.addingTimeInterval(120)   // 2-minute window
        // Drop .second — DeviceActivitySchedule rounds to the minute
        let startComponents = calendar.dateComponents([.hour, .minute], from: fireDate)
        let endComponents   = calendar.dateComponents([.hour, .minute], from: windowEnd)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd:   endComponents,
            repeats: false
        )
        do {
            try center.startMonitoring(DeviceActivityName("tuff.breakEnd"), during: schedule)
            print("[Tuff] breakEnd schedule registered: fires at \(fireDate)")
        } catch {
            print("[Tuff] Failed to register breakEnd schedule: \(error)")
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
        // Cancel the one-shot extension schedule so it doesn't fire spuriously
        DeviceActivityCenter().stopMonitoring([DeviceActivityName("tuff.breakEnd")])
        blockSelectedApps()
        ensureLockedLiveActivity()
        startShieldHeartbeat()

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

        // `hasEnded` excludes leagues whose scheduled endDate has passed — we
        // shouldn't refund ledger entries on settled leagues.
        let activeLeagues = leagues.filter { $0.isActive && !$0.hasEnded }
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
                        let todayKey = League.dayKey(for: Date())
                        try await docRef.updateData([
                            "ledger.\(uid).boughtCents":   FieldValue.increment(-Int64(refundCents)),
                            "ledger.\(uid).boughtMinutes": FieldValue.increment(-Int64(refundMinutes)),
                            "dailyLedger.\(todayKey).\(uid).boughtCents": FieldValue.increment(-Int64(refundCents)),
                            "dailyLedger.\(todayKey).\(uid).boughtMinutes": FieldValue.increment(-Int64(refundMinutes))
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
        startShieldHeartbeat()
    }

    /// Register 12 × 2-hour DeviceActivity schedules as a keep-alive fallback.
    ///
    /// Why 12, not 24 or 96?
    /// DeviceActivityCenter has a per-app slot cap (~20 historically; not
    /// officially documented for iOS 17+). When you exceed the cap,
    /// `try? center.startMonitoring(...)` SILENTLY drops slots — so the
    /// extension stops getting woken to refresh the shield and the system's
    /// `ManagedSettings` configuration drifts, which surfaces as "blocking
    /// fades away after a while".
    ///
    /// 12 slots leaves comfortable headroom for the one-shot
    /// `tuff.breakEnd` schedule (registered when a break starts) AND for any
    /// future activity-monitor work without re-introducing the saturation
    /// failure mode. Worst-case latency for re-applying the shield via the
    /// extension is now ≤2 hours, which is fine because both
    /// `intervalDidStart` AND `intervalDidEnd` now re-write the shield
    /// (see TuffDeviceActivity), so coverage is effectively every ~60 min.
    ///
    /// Only registers once per app session; subsequent calls are no-ops.
    func registerBlockingSchedules() {
        guard isAuthorized else { return }
        guard !schedulesRegistered else { return }
        schedulesRegistered = true

        let center = DeviceActivityCenter()

        // Remove legacy slot names from previous app versions so they don't
        // occupy precious slots forever. Old layouts: 96 × 15min, 24 × 1h.
        let legacy15Min = (0...95).map { DeviceActivityName("tuff.block.\($0)") }
        center.stopMonitoring(legacy15Min)

        let calendar = Calendar.current
        let base = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: Date())!
        var registered = 0
        var failed: [Int] = []

        // 12 × 2-hour slots = full day, well under the slot cap.
        for slotIndex in 0..<12 {
            let startDate = base.addingTimeInterval(TimeInterval(slotIndex * 2 * 3600))
            let endDate   = startDate.addingTimeInterval(2 * 60 * 60 - 1) // 1h 59m 59s window
            let start = calendar.dateComponents([.hour, .minute], from: startDate)
            let end   = calendar.dateComponents([.hour, .minute], from: endDate)
            let schedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: true)
            do {
                try center.startMonitoring(DeviceActivityName("tuff.keepalive.\(slotIndex)"),
                                           during: schedule)
                registered += 1
            } catch {
                failed.append(slotIndex)
                print("[Tuff] keepalive slot \(slotIndex) FAILED: \(error.localizedDescription)")
            }
        }
        print("[Tuff] keepalive schedules registered: \(registered)/12 (failed: \(failed))")
    }

    private var schedulesRegistered = false

    /// Purchase a break: unblock for `minutes`, then atomically increment each active league's
    /// ledger entry for this user using FieldValue.increment (no transaction needed).
    func buyBreak(minutes: Int, uid: String, leagues: [League]) async {
        startBlockTimer(duration: TimeInterval(minutes * 60))

        // `hasEnded` excludes leagues whose scheduled endDate has passed — we
        // shouldn't charge new breaks against a settled league.
        let activeLeagues = leagues.filter { $0.isActive && !$0.hasEnded }
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
                        let todayKey = League.dayKey(for: Date())
                        // ledger.{uid}.boughtCents / boughtMinutes are top-level map fields —
                        // FieldValue.increment is atomic and needs no transaction.
                        try await docRef.updateData([
                            "ledger.\(uid).boughtCents":   FieldValue.increment(Int64(costCents)),
                            "ledger.\(uid).boughtMinutes": FieldValue.increment(Int64(minutes)),
                            "dailyLedger.\(todayKey).\(uid).boughtCents": FieldValue.increment(Int64(costCents)),
                            "dailyLedger.\(todayKey).\(uid).boughtMinutes": FieldValue.increment(Int64(minutes))
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

        // Give a 90-second buffer past the break end before iOS shows the stale spinner.
        // The one-shot DeviceActivity schedule + recheckAuthorization will update the
        // activity to locked state within that window.
        let staleDate = endDate.addingTimeInterval(90)
        if let existing = liveActivity {
            Task {
                await existing.update(ActivityContent(state: breakState, staleDate: staleDate))
            }
        } else {
            requestFreshActivity(state: breakState)
        }
    }

    private func requestFreshActivity(state: BlockTimerAttributes.ContentState) {
        let previousActivity = liveActivity
        liveActivity = nil
        // Buffer 90s past break end before iOS shows the stale spinner
        let stale: Date? = state.isOnBreak ? state.endDate.addingTimeInterval(90) : nil
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
            UserDefaults.standard.set(true, forKey: Self.hasAuthorizedKey)
            registerBlockingSchedules()
            // Start blocking immediately — no welcome break.
            applyAlwaysOnBlocking()
            print("[Tuff] Already authorized ✓ (shield applied)")
            return
        }

        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
            UserDefaults.standard.set(true, forKey: Self.hasAuthorizedKey)
            registerBlockingSchedules()
            // Engage the shield the instant the user grants permission so
            // there's no "automatic break" window after onboarding.
            applyAlwaysOnBlocking()
            print("[Tuff] Screen Time authorized ✓ (shield applied)")
        } catch {
            print("[Tuff] Screen Time auth failed: \(error)")
            isAuthorized = false
        }
    }

    // MARK: - App Blocking

    /// Blocks all app categories and web domains, exempting any apps the user has
    /// selected via `allowedAppSelection` (configured by the league creator).
    func blockSelectedApps() {
        guard let store else {
            print("[Tuff] blockSelectedApps: store is nil")
            return
        }
        let exemptTokens = allowedAppSelection.applicationTokens
        if exemptTokens.isEmpty {
            store.shield.applicationCategories = .all()
        } else {
            store.shield.applicationCategories = .all(except: exemptTokens)
        }
        store.shield.webDomainCategories = .all()
        store.application.denyAppRemoval = true
        isActivelyBlocking = true
        print("[Tuff] Shield applied — all apps blocked\(exemptTokens.isEmpty ? "" : " (except \(exemptTokens.count) allowed)")")
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
