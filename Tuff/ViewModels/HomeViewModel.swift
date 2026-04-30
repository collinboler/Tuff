import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

@MainActor
class HomeViewModel: ObservableObject {
    @Published var currentUser: TuffUser = .currentUser
    @Published var selectedCarouselUser: TuffUser = .currentUser
    @Published var leagues: [League] = []
    @Published var selectedLeague: League?
    @Published var showLeagueDetail = false
    @Published var showCreateLeague = false
    @Published var showJoinLeague = false

    /// A league whose end date has just passed that we want to surface to the
    /// user in the final-results sheet. The UI observes this to auto-present
    /// `LeagueEndedView`; `dismissEndedLeagueSheet()` clears it.
    @Published var endedLeagueToShow: League?
    @Published var showLeagueEndedSheet = false

    private var leaguesListener: ListenerRegistration?
    private var implicitFriendsListener: ListenerRegistration?
    private var notificationsListener: ListenerRegistration?
    private var resolvedPhotoURLsByUID: [String: String] = [:]
    private var photoFetchInFlight: Set<String> = []
    /// Friend uids (excluding self) whose timer is still alive. Refreshed by
    /// `ImplicitFriendsService` whenever leagues change.
    private var implicitFriendUids: [String: ImplicitFriendEntry] = [:]
    /// League IDs for which we've already notified / shown the end sheet
    /// during this app lifetime — prevents repeatedly firing when Firestore
    /// snapshots re-emit.
    private var processedEndedLeagueIDs: Set<String> = []
    /// Per-league record of who held first place during the previous snapshot.
    /// Used to fire the "You're winning in [League]" notification when the
    /// current user takes the lead more than 24h after the league started.
    private var previousLeaderUidByLeague: [String: String] = [:]

    /// Snapshot of `boughtCents` per (leagueId, uid). Used by
    /// `detectBuyTimeLaggards` to detect when *another* member transitions
    /// from 0 → >0 cents (i.e. just made a buy).
    private var previousBoughtCentsByLeague: [String: [String: Int]] = [:]

    init() {
        loadCurrentUser()
        startLeaguesListener()
        startImplicitFriendsListener()
        startNotificationsListener()
    }

    private func startImplicitFriendsListener() {
        implicitFriendsListener = ImplicitFriendsService.shared.observe { [weak self] entries in
            guard let self else { return }
            var byUid: [String: ImplicitFriendEntry] = [:]
            for entry in entries { byUid[entry.uid] = entry }
            self.implicitFriendUids = byUid
            self.refreshSelectedCarouselUser()
            self.objectWillChange.send()
        }
    }

    /// Listens for cross-user notifications written into
    /// `users/{myUid}/notifications` (e.g. someone paying me out for a league).
    /// New entries are surfaced as local notifications and then marked
    /// `delivered` so they aren't replayed on next launch.
    private func startNotificationsListener() {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        notificationsListener = db.collection("users").document(myUid)
            .collection("notifications")
            .whereField("delivered", isEqualTo: false)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                Task { @MainActor in
                    for doc in docs {
                        let data = doc.data()
                        let title = data["title"] as? String ?? "Tuff"
                        let body  = data["body"]  as? String ?? ""
                        NotificationManager.shared.fireImmediate(
                            id: "remote_\(doc.documentID)",
                            title: title,
                            body: body
                        )
                        try? await doc.reference.updateData([
                            "delivered": true,
                            "deliveredAt": FieldValue.serverTimestamp()
                        ])
                    }
                    _ = self
                }
            }
    }

    // MARK: - Load real user

    private func loadCurrentUser() {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        let uid = firebaseUser.uid
        Task {
            let db = Firestore.firestore()
            guard let doc = try? await db.collection("users").document(uid).getDocument(),
                  let data = doc.data() else { return }
            let firstName = data["firstName"] as? String ?? ""
            let lastName  = data["lastName"]  as? String ?? ""
            let fullName  = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            let username  = data["username"]  as? String ?? firebaseUser.phoneNumber ?? ""
            let methodRaw = data["paymentMethod"] as? String ?? PaymentMethod.none.rawValue
            let user = TuffUser(
                id: UUID(),
                uid: uid,
                name: fullName.isEmpty ? "You" : fullName,
                username: username,
                imageName: "",
                photoURL: data["photoURL"] as? String,
                isCurrentUser: true,
                screenTimeMinutes: data["screenTimeMinutes"] as? Int ?? 0,
                totalLeagues: data["totalLeagues"] as? Int ?? 0,
                leaguesWon: data["leaguesWon"] as? Int ?? 0,
                totalEarnings: data["totalEarnings"] as? Double ?? 0,
                paymentMethod: PaymentMethod(rawValue: methodRaw) ?? .none,
                paymentID: data["paymentID"] as? String ?? ""
            )
            self.currentUser = user
            if let photoURL = user.photoURL, !photoURL.isEmpty {
                if photoURL.lowercased().hasPrefix("gs://") {
                    self.queuePhotoURLResolution(uid: uid, rawURL: photoURL)
                } else {
                    self.resolvedPhotoURLsByUID[uid] = photoURL
                }
            }
            self.refreshSelectedCarouselUser()
        }
    }

    // MARK: - Firestore leagues listener

    private func startLeaguesListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        leaguesListener = db.collection("leagues")
            .whereField("memberUids", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                Task { @MainActor in
                    // All leaderboard data (boughtCents/boughtMinutes) lives in the league
                    // document's `ledger` map and is parsed directly by League.from().
                    // No secondary user-document reads are needed.
                    let newLeagues = docs.compactMap { League.from($0.data(), id: $0.documentID) }
                    self.detectFirstPlaceTransitions(newLeagues: newLeagues)
                    self.detectBuyTimeLaggards(newLeagues: newLeagues)
                    self.leagues = newLeagues
                    self.resolveMissingMemberPhotoURLs()
                    self.refreshSelectedCarouselUser()
                    self.checkForNewlyEndedLeagues()
                    Task { await ImplicitFriendsService.shared.refreshFromAllLeagues(newLeagues) }
                }
            }
    }

    private func resolveMissingMemberPhotoURLs() {
        let candidateUIDs = Set(leagues
            .flatMap { $0.members }
            .filter { !$0.isDQ }
            .map { $0.user.uid }
            .filter { !$0.isEmpty })

        let missingUIDs = candidateUIDs.filter {
            resolvedPhotoURLsByUID[$0] == nil && !photoFetchInFlight.contains($0)
        }

        guard !missingUIDs.isEmpty else { return }

        for uid in missingUIDs {
            queuePhotoURLResolution(uid: uid, rawURL: nil)
        }
    }

    private func queuePhotoURLResolution(uid: String, rawURL: String?) {
        guard !uid.isEmpty else { return }
        guard !photoFetchInFlight.contains(uid) else { return }

        if let rawURL, !rawURL.isEmpty,
           !rawURL.lowercased().hasPrefix("gs://") {
            resolvedPhotoURLsByUID[uid] = rawURL
            return
        }

        photoFetchInFlight.insert(uid)
        Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.photoFetchInFlight.remove(uid)
                }
            }

            var resolved: String? = nil

            if let rawURL, rawURL.lowercased().hasPrefix("gs://") {
                resolved = try? await Storage.storage().reference(forURL: rawURL).downloadURL().absoluteString
            }

            if resolved == nil {
                let db = Firestore.firestore()
                if let doc = try? await db.collection("users").document(uid).getDocument(),
                   let data = doc.data(),
                   let userPhotoURL = data["photoURL"] as? String,
                   !userPhotoURL.isEmpty {
                    if userPhotoURL.lowercased().hasPrefix("gs://") {
                        resolved = try? await Storage.storage().reference(forURL: userPhotoURL).downloadURL().absoluteString
                    } else {
                        resolved = userPhotoURL
                    }
                }
            }

            guard let resolved, !resolved.isEmpty else { return }
            await MainActor.run {
                self.resolvedPhotoURLsByUID[uid] = resolved
                self.refreshSelectedCarouselUser()
            }
        }
    }

    /// Immediately removes the refunded cost from local league state so the leaderboard
    /// updates before the Firestore round-trip completes.
    func applyOptimisticRefund(uid: String, refundMinutes: Int) {
        leagues = leagues.map { league in
            guard league.isActive, !league.hasEnded else { return league }
            let refundCents = max(1, Int(round(Double(refundMinutes) / 60.0 * Double(league.pricePerHourCents))))
            var updated = league
            updated.members = league.members.map { member in
                guard member.user.uid == uid else { return member }
                return LeagueMember(
                    id: member.id, user: member.user,
                    currentScreenTime: member.currentScreenTime,
                    rank: member.rank,
                    lastUpdated: Date(),
                    boughtCents: max(0, member.boughtCents - refundCents),
                    boughtMinutes: max(0, member.boughtMinutes - refundMinutes),
                    todayBoughtCents: max(0, member.todayBoughtCents - refundCents),
                    isDQ: member.isDQ
                )
            }
            return updated
        }
        refreshSelectedCarouselUser()
    }

    /// Immediately applies the break cost to local league state so the leaderboard
    /// updates before the Firestore round-trip completes.
    func applyOptimisticBreakCharge(uid: String, minutes: Int) {
        leagues = leagues.map { league in
            guard league.isActive, !league.hasEnded else { return league }
            let costCents = max(1, Int(round(Double(minutes) / 60.0 * Double(league.pricePerHourCents))))
            var updated = league
            updated.members = league.members.map { member in
                guard member.user.uid == uid else { return member }
                return LeagueMember(
                    id: member.id, user: member.user,
                    currentScreenTime: member.currentScreenTime,
                    rank: member.rank,
                    lastUpdated: Date(),
                    boughtCents: member.boughtCents + costCents,
                    boughtMinutes: member.boughtMinutes + minutes,
                    todayBoughtCents: member.todayBoughtCents + costCents,
                    isDQ: member.isDQ
                )
            }
            return updated
        }
        refreshSelectedCarouselUser()
    }

    // MARK: - League ending detection

    /// Finds leagues whose `endDate` has passed but haven't been shown to this
    /// user yet, fires a local notification, and surfaces the first one for
    /// the UI to present.
    private func checkForNewlyEndedLeagues() {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }

        let seen = UserDefaults.standard.seenEndedLeagueIDs(for: uid)
        let newlyEnded = leagues.filter { league in
            league.hasEnded
                && !seen.contains(league.id)
                && !processedEndedLeagueIDs.contains(league.id)
        }
        guard !newlyEnded.isEmpty else { return }

        for league in newlyEnded {
            processedEndedLeagueIDs.insert(league.id)

            let winnerName = league.winner?.user.name ?? "Nobody"
            let userWon = league.winner?.user.uid == uid
            let net = league.netOutcomeCents(forUid: uid)

            NotificationManager.shared.scheduleLeagueEndedNotification(
                leagueId: league.id,
                leagueName: league.name,
                winnerName: winnerName,
                userWon: userWon,
                netOutcomeCents: net
            )
        }

        // Present the most recently-ended league first if the UI isn't already
        // showing one.
        if endedLeagueToShow == nil, !showLeagueEndedSheet {
            endedLeagueToShow = newlyEnded.sorted { $0.endDate > $1.endDate }.first
            if endedLeagueToShow != nil {
                showLeagueEndedSheet = true
            }
        }
    }

    /// Called by the UI when the user dismisses the ending sheet.
    /// Marks the league as seen so it isn't re-presented on next launch.
    func dismissEndedLeagueSheet() {
        if let league = endedLeagueToShow,
           let uid = Auth.auth().currentUser?.uid, !uid.isEmpty {
            UserDefaults.standard.markLeagueEndSeen(league.id, for: uid)
        }
        endedLeagueToShow = nil
        showLeagueEndedSheet = false
    }

    /// Explicit request to view a league's ending screen (from a tap on an
    /// already-ended league card). Doesn't change the "seen" state until the
    /// user dismisses.
    func presentEndedLeague(_ league: League) {
        endedLeagueToShow = league
        showLeagueEndedSheet = true
    }

    deinit {
        leaguesListener?.remove()
        implicitFriendsListener?.remove()
        notificationsListener?.remove()
    }

    // MARK: - First-place detection

    /// Compares the leader (lowest boughtCents, non-DQ) in each new snapshot
    /// against the previous snapshot. If the current user just took 1st place
    /// AND the league has been running for at least 24h, fire a local
    /// "You're winning" notification.
    private func detectFirstPlaceTransitions(newLeagues: [League]) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        let now = Date()

        for league in newLeagues {
            guard !league.hasEnded else {
                previousLeaderUidByLeague[league.id] = nil
                continue
            }
            let active = league.members.filter { !$0.isDQ }
            guard let leader = active.min(by: { $0.boughtCents < $1.boughtCents }) else { continue }
            let leaderUid = leader.user.uid
            let previous = previousLeaderUidByLeague[league.id]
            previousLeaderUidByLeague[league.id] = leaderUid

            // Only notify on actual transitions where I'm the new leader. Skip
            // the very first snapshot (`previous == nil`) so we don't spam the
            // user with "you're winning" the moment we open the app.
            guard previous != nil, previous != leaderUid, leaderUid == uid else { continue }
            guard now.timeIntervalSince(league.startDate) >= 24 * 60 * 60 else { continue }

            NotificationManager.shared.scheduleTookFirstPlaceNotification(
                leagueId: league.id,
                leagueName: league.name
            )
        }
    }

    // MARK: - Laggard detection

    /// When another member just bought time in a league older than 2 days and
    /// I haven't bought anything yet, schedule a 2-minute delayed local
    /// notification reminding me I'm falling behind. Cancels the pending
    /// reminder if I subsequently buy time before the 2 minutes elapses.
    ///
    /// Each device runs this independently against its own listener snapshot,
    /// so the notification fires on the laggard's phone without needing a
    /// server-side push.
    private func detectBuyTimeLaggards(newLeagues: [League]) {
        guard let myUid = Auth.auth().currentUser?.uid, !myUid.isEmpty else { return }
        let now = Date()
        let twoDays: TimeInterval = 2 * 24 * 60 * 60

        for league in newLeagues {
            guard !league.hasEnded else {
                previousBoughtCentsByLeague[league.id] = nil
                continue
            }

            // Build a fresh snapshot for next iteration.
            var currentSnapshot: [String: Int] = [:]
            for m in league.members {
                currentSnapshot[m.user.uid] = m.boughtCents
            }
            let previousSnapshot = previousBoughtCentsByLeague[league.id]
            defer { previousBoughtCentsByLeague[league.id] = currentSnapshot }

            // Need a baseline + the league must be old enough for the rule to apply.
            guard let previous = previousSnapshot else { continue }
            guard now.timeIntervalSince(league.startDate) >= twoDays else { continue }

            // Did I just buy time? Cancel any pending laggard reminder for myself.
            let myCurrent = currentSnapshot[myUid] ?? 0
            let myPrevious = previous[myUid] ?? 0
            if myPrevious == 0 && myCurrent > 0 {
                NotificationManager.shared.cancelLaggardReminder(
                    leagueId: league.id,
                    laggardUid: myUid
                )
            }

            // Only schedule a reminder for myself if I'm the laggard.
            guard myCurrent == 0 else { continue }

            // Did *anyone else* transition from 0 → >0 cents in this snapshot?
            let someoneJustBought = league.members.contains { m in
                guard m.user.uid != myUid else { return false }
                let prev = previous[m.user.uid] ?? 0
                let cur  = currentSnapshot[m.user.uid] ?? 0
                return prev == 0 && cur > 0
            }
            guard someoneJustBought else { continue }

            // Show my own name in the body — the reminder is a self-callout
            // ("Brian has not bought anything yet"). Falls back to "You" when
            // the user record hasn't loaded yet.
            let myName: String = {
                if !currentUser.name.isEmpty && currentUser.name != "You" {
                    return currentUser.name
                }
                if let me = league.members.first(where: { $0.user.uid == myUid }),
                   !me.user.name.isEmpty {
                    return me.user.name
                }
                return "You"
            }()

            NotificationManager.shared.scheduleLaggardReminder(
                leagueId: league.id,
                laggardUid: myUid,
                laggardName: myName
            )
        }
    }

    // MARK: - Archive

    /// Active leagues = anything not yet ended OR ended-but-not-paid-out by me.
    /// These render in the main "LEAGUES" list so I can still pay out from them.
    var activeLeagues: [League] {
        guard let uid = Auth.auth().currentUser?.uid else { return leagues }
        return leagues.filter { !$0.hasEnded || !$0.isPaidOut(uid: uid) }
    }

    /// Archived leagues = ended AND I've confirmed payout/settlement.
    /// Sorted newest-first so the most recently settled appears at the top.
    var archivedLeagues: [League] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        return leagues
            .filter { $0.hasEnded && $0.isPaidOut(uid: uid) }
            .sorted { $0.endDate > $1.endDate }
    }

    // MARK: - Join by invite code

    func joinLeague(inviteCode: String) async -> String? {
        guard let uid = Auth.auth().currentUser?.uid else { return "Not signed in" }
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("leagues")
                .whereField("inviteCode", isEqualTo: inviteCode.uppercased())
                .limit(to: 1)
                .getDocuments()
            guard let doc = snap.documents.first else { return "No league found with that code" }
            let leagueId = doc.documentID
            let existingUids = doc.data()["memberUids"] as? [String] ?? []
            if existingUids.contains(uid) { return nil }

            let userDoc = try? await db.collection("users").document(uid).getDocument()
            let userData = userDoc?.data()
            let firstName = userData?["firstName"] as? String ?? ""
            let lastName  = userData?["lastName"]  as? String ?? ""
            let username  = userData?["username"]  as? String ?? ""
            var memberProfile: [String: Any] = [
                "uid": uid,
                "name": "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces),
                "username": username,
                "screenTimeMinutes": 0,
                "joinedAt": Timestamp(date: Date()),
                "paymentMethod": userData?["paymentMethod"] as? String ?? PaymentMethod.none.rawValue,
                "paymentID": userData?["paymentID"] as? String ?? ""
            ]
            if let photoURL = userData?["photoURL"] as? String {
                memberProfile["photoURL"] = photoURL
            }

            try await db.collection("leagues").document(leagueId).updateData([
                "memberUids": FieldValue.arrayUnion([uid]),
                "memberProfiles": FieldValue.arrayUnion([memberProfile])
            ])
            // Refresh implicit-friends ledger for both me and the new co-members.
            await ImplicitFriendsService.shared.refreshAfterJoin(leagueId: leagueId)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Carousel

    private struct CarouselAggregate {
        var user: TuffUser
        var dailyCents: Int
    }

    private func userKey(for user: TuffUser) -> String {
        user.uid.isEmpty ? user.id.uuidString : user.uid
    }

    /// Carousel = current user + every implicit friend (last 30 days).
    /// Daily-spent figures still come from active leagues so the panel updates
    /// in real time, but absence from a current league no longer hides a
    /// friend — they stay visible until their implicit-friend timer expires.
    private func buildCarouselAggregates() -> [String: CarouselAggregate] {
        var aggregates: [String: CarouselAggregate] = [:]

        let currentKey = userKey(for: currentUser)
        aggregates[currentKey] = CarouselAggregate(user: currentUser, dailyCents: 0)

        for entry in implicitFriendUids.values {
            guard !entry.uid.isEmpty, entry.uid != currentUser.uid else { continue }
            let user = TuffUser(
                id: UUID(),
                uid: entry.uid,
                name: entry.name,
                username: entry.username,
                imageName: "",
                photoURL: entry.photoURL.flatMap { $0.isEmpty ? nil : $0 },
                isCurrentUser: false,
                screenTimeMinutes: 0,
                totalLeagues: 0,
                leaguesWon: 0,
                totalEarnings: 0,
                paymentMethod: PaymentMethod(rawValue: entry.paymentMethod) ?? .none,
                paymentID: entry.paymentID
            )
            aggregates[entry.uid] = CarouselAggregate(user: user, dailyCents: 0)
        }

        for league in leagues {
            // Ended leagues are settled — their today/daily spend should no
            // longer roll into the live "$X today" figure shown in the
            // carousel/member panel.
            guard !league.hasEnded else { continue }
            for member in league.members {
                guard !member.isDQ else { continue }
                let key = userKey(for: member.user)
                var incoming = member.user
                if (incoming.photoURL ?? "").isEmpty,
                   let resolved = resolvedPhotoURLsByUID[key] {
                    incoming.photoURL = resolved
                }
                if let rawURL = incoming.photoURL,
                   rawURL.lowercased().hasPrefix("gs://") {
                    queuePhotoURLResolution(uid: key, rawURL: rawURL)
                }
                let todayCents = max(0, member.todayBoughtCents)

                if var existing = aggregates[key] {
                    if incoming.screenTimeMinutes > existing.user.screenTimeMinutes {
                        existing.user.screenTimeMinutes = incoming.screenTimeMinutes
                    }
                    if existing.user.name.isEmpty { existing.user.name = incoming.name }
                    if existing.user.username.isEmpty { existing.user.username = incoming.username }
                    if existing.user.imageName.isEmpty { existing.user.imageName = incoming.imageName }
                    if existing.user.photoURL == nil { existing.user.photoURL = incoming.photoURL }
                    if (existing.user.photoURL ?? "").isEmpty,
                       let resolved = resolvedPhotoURLsByUID[key] {
                        existing.user.photoURL = resolved
                    }
                    existing.user.isCurrentUser = existing.user.isCurrentUser || incoming.isCurrentUser
                    existing.dailyCents += todayCents
                    aggregates[key] = existing
                } else {
                    aggregates[key] = CarouselAggregate(user: incoming, dailyCents: todayCents)
                }
            }
        }

        return aggregates
    }

    var carouselUsers: [TuffUser] {
        let aggregates = buildCarouselAggregates()
        let sortedKeys = aggregates.keys.sorted { lhs, rhs in
            let left = aggregates[lhs]?.dailyCents ?? 0
            let right = aggregates[rhs]?.dailyCents ?? 0
            if left == right {
                let leftName = aggregates[lhs]?.user.name ?? ""
                let rightName = aggregates[rhs]?.user.name ?? ""
                return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
            }
            return left < right
        }
        return sortedKeys.compactMap { aggregates[$0]?.user }
    }

    func dailySpentCents(for user: TuffUser) -> Int {
        buildCarouselAggregates()[userKey(for: user)]?.dailyCents ?? 0
    }

    var overallRank: Int {
        (carouselUsers.firstIndex(where: { $0.isCurrentUser }) ?? 0) + 1
    }

    var totalParticipants: Int { carouselUsers.count }

    func selectCarouselUser(at index: Int) {
        let users = carouselUsers
        guard index >= 0 && index < users.count else { return }
        let incoming = users[index]
        if userKey(for: incoming) == userKey(for: selectedCarouselUser) { return }
        Task { @MainActor in
            // Defer publishing to avoid mutating during view update cycle
            self.selectedCarouselUser = incoming
        }
    }

    func selectLeague(_ league: League) {
        Task { @MainActor in
            // Defer publishing to avoid mutating during view update cycle
            self.selectedLeague = league
            self.showLeagueDetail = true
        }
    }

    private func refreshSelectedCarouselUser() {
        let users = carouselUsers
        guard !users.isEmpty else {
            selectedCarouselUser = currentUser
            return
        }

        let selectedKey = userKey(for: selectedCarouselUser)
        let currentKey = userKey(for: currentUser)

        if selectedKey == currentKey,
           let latestCurrent = users.first(where: { userKey(for: $0) == currentKey }) {
            selectedCarouselUser = latestCurrent
            return
        }

        if let existing = users.first(where: { userKey(for: $0) == selectedKey }) {
            selectedCarouselUser = existing
        } else {
            selectedCarouselUser = users.first ?? currentUser
        }
    }
}

// MARK: - Seen ended-league persistence
// Tracked per-uid so that multiple users on the same device each get their
// own ending prompts once (and only once) per league.
extension UserDefaults {
    private static let seenEndedLeaguesKeyPrefix = "seenEndedLeagues_"

    func seenEndedLeagueIDs(for uid: String) -> Set<String> {
        let key = Self.seenEndedLeaguesKeyPrefix + uid
        return Set(stringArray(forKey: key) ?? [])
    }

    func markLeagueEndSeen(_ leagueId: String, for uid: String) {
        let key = Self.seenEndedLeaguesKeyPrefix + uid
        var existing = seenEndedLeagueIDs(for: uid)
        existing.insert(leagueId)
        set(Array(existing), forKey: key)
    }
}
