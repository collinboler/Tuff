import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class HomeViewModel: ObservableObject {
    @Published var currentUser: TuffUser = .currentUser
    @Published var selectedCarouselUser: TuffUser = .currentUser
    @Published var leagues: [League] = []
    @Published var selectedLeague: League?
    @Published var showLeagueDetail = false
    @Published var showCreateLeague = false
    @Published var showJoinLeague = false

    private var leaguesListener: ListenerRegistration?

    init() {
        loadCurrentUser()
        startLeaguesListener()
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
            let user = TuffUser(
                id: UUID(),
                uid: uid,
                name: fullName.isEmpty ? "You" : fullName,
                username: username,
                imageName: "",
                isCurrentUser: true,
                screenTimeMinutes: data["screenTimeMinutes"] as? Int ?? 0,
                totalLeagues: data["totalLeagues"] as? Int ?? 0,
                leaguesWon: data["leaguesWon"] as? Int ?? 0,
                totalEarnings: data["totalEarnings"] as? Double ?? 0
            )
            self.currentUser = user
            if self.selectedCarouselUser.isCurrentUser {
                self.selectedCarouselUser = user
            }
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
                    self.leagues = docs.compactMap { League.from($0.data(), id: $0.documentID) }
                }
            }
    }

    /// Immediately removes the refunded cost from local league state so the leaderboard
    /// updates before the Firestore round-trip completes.
    func applyOptimisticRefund(uid: String, refundMinutes: Int) {
        leagues = leagues.map { league in
            guard league.isActive else { return league }
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
                    isDQ: member.isDQ
                )
            }
            return updated
        }
    }

    /// Immediately applies the break cost to local league state so the leaderboard
    /// updates before the Firestore round-trip completes.
    func applyOptimisticBreakCharge(uid: String, minutes: Int) {
        leagues = leagues.map { league in
            guard league.isActive else { return league }
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
                    isDQ: member.isDQ
                )
            }
            return updated
        }
    }

    deinit {
        leaguesListener?.remove()
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

            let userDoc = try? await db.collection("users").document(uid).getDocument()
            let userData = userDoc?.data()
            let firstName = userData?["firstName"] as? String ?? ""
            let lastName  = userData?["lastName"]  as? String ?? ""
            let username  = userData?["username"]  as? String ?? ""
            let memberProfile: [String: Any] = [
                "uid": uid,
                "name": "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces),
                "username": username,
                "screenTimeMinutes": 0
            ]

            try await db.collection("leagues").document(leagueId).updateData([
                "memberUids": FieldValue.arrayUnion([uid]),
                "memberProfiles": FieldValue.arrayUnion([memberProfile])
            ])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Carousel

    var carouselUsers: [TuffUser] {
        var seen = Set<String>()
        var result: [TuffUser] = []
        // Current user always first
        let key = currentUser.uid.isEmpty ? currentUser.id.uuidString : currentUser.uid
        seen.insert(key)
        result.append(currentUser)
        // Add league members
        for league in leagues {
            for member in league.members {
                let k = member.user.uid.isEmpty ? member.user.id.uuidString : member.user.uid
                if seen.insert(k).inserted {
                    result.append(member.user)
                }
            }
        }
        return result.sorted { $0.screenTimeMinutes < $1.screenTimeMinutes }
    }

    var overallRank: Int {
        let sorted = carouselUsers.sorted { $0.screenTimeMinutes < $1.screenTimeMinutes }
        return (sorted.firstIndex(where: { $0.isCurrentUser }) ?? 0) + 1
    }

    var totalParticipants: Int { carouselUsers.count }

    func selectCarouselUser(at index: Int) {
        let users = carouselUsers
        guard index >= 0 && index < users.count else { return }
        selectedCarouselUser = users[index]
    }

    func selectLeague(_ league: League) {
        selectedLeague = league
        showLeagueDetail = true
    }
}
