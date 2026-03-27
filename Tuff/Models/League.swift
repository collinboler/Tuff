import Foundation
import FirebaseFirestore
import FirebaseAuth

struct League: Identifiable {
    let id: String
    var name: String
    var createdBy: String   // Firebase uid
    var startDate: Date
    var endDate: Date
    /// Virtual cost rate in cents per hour (e.g. 20 = $0.20/hr).
    var pricePerHourCents: Int
    var inviteCode: String
    var isActive: Bool
    var members: [LeagueMember]

    /// Total virtual pool = sum of all members' boughtCents.
    var poolCents: Int { members.reduce(0) { $0 + $1.boughtCents } }
    var poolDollars: Double { Double(poolCents) / 100.0 }

    var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    /// Winner takes all — person with lowest boughtCents wins the pool.
    var payoutBreakdown: [(place: String, amount: String)] {
        [("1st Place — Lowest spent wins", String(format: "$%.2f pool", poolDollars))]
    }

    /// Sorted ascending by boughtCents (0 = winning; most disciplined user first).
    var sortedMembers: [LeagueMember] { members.sorted { $0.boughtCents < $1.boughtCents } }

    // MARK: - Firestore parsing

    static func from(_ data: [String: Any], id: String) -> League? {
        guard let name = data["name"] as? String,
              let startTs = data["startDate"] as? Timestamp,
              let endTs = data["endDate"] as? Timestamp else { return nil }

        let currentUID = Auth.auth().currentUser?.uid ?? ""

        // ledger is a top-level map { uid: { boughtCents: Int, boughtMinutes: Int } }
        // This allows atomic FieldValue.increment updates without transactions.
        let ledger = data["ledger"] as? [String: [String: Any]] ?? [:]

        let memberProfiles = data["memberProfiles"] as? [[String: Any]] ?? []
        let members: [LeagueMember] = memberProfiles.enumerated().map { i, profile in
            let uid = profile["uid"] as? String ?? ""
            let entry = ledger[uid] ?? [:]
            let memberUser = TuffUser(
                id: UUID(),
                uid: uid,
                name: profile["name"] as? String ?? "Unknown",
                username: profile["username"] as? String ?? "",
                imageName: "",
                isCurrentUser: uid == currentUID,
                screenTimeMinutes: profile["screenTimeMinutes"] as? Int ?? 0,
                totalLeagues: 0,
                leaguesWon: 0,
                totalEarnings: 0
            )
            return LeagueMember(
                id: UUID(),
                user: memberUser,
                currentScreenTime: Double((profile["screenTimeMinutes"] as? Int ?? 0) * 60),
                rank: i + 1,
                lastUpdated: Date(),
                boughtCents: entry["boughtCents"] as? Int ?? 0,
                boughtMinutes: entry["boughtMinutes"] as? Int ?? 0
            )
        }

        return League(
            id: id,
            name: name,
            createdBy: data["createdBy"] as? String ?? "",
            startDate: startTs.dateValue(),
            endDate: endTs.dateValue(),
            pricePerHourCents: data["pricePerHourCents"] as? Int ?? 20,
            inviteCode: data["inviteCode"] as? String ?? "",
            isActive: data["isActive"] as? Bool ?? true,
            members: members
        )
    }
}

struct LeagueHistoryEntry: Identifiable {
    let id: UUID
    let leagueName: String
    let startDate: Date
    let endDate: Date
    let placement: Int
    let earnings: Double

    var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    var earningsText: String {
        earnings >= 0 ? "+$\(Int(earnings))" : "-$\(Int(abs(earnings)))"
    }
}

extension LeagueHistoryEntry {
    static func makeSampleDate(month: Int, day: Int, year: Int = 2026) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components) ?? Date()
    }

    static var sampleHistory: [LeagueHistoryEntry] {
        [
            LeagueHistoryEntry(id: UUID(), leagueName: "Frosh Floor",
                startDate: makeSampleDate(month: 2, day: 17),
                endDate: makeSampleDate(month: 2, day: 23),
                placement: 1, earnings: 45),
            LeagueHistoryEntry(id: UUID(), leagueName: "Winter Break",
                startDate: makeSampleDate(month: 12, day: 20, year: 2025),
                endDate: makeSampleDate(month: 1, day: 2),
                placement: 2, earnings: 28),
            LeagueHistoryEntry(id: UUID(), leagueName: "Tiger Inn",
                startDate: makeSampleDate(month: 1, day: 20),
                endDate: makeSampleDate(month: 1, day: 26),
                placement: 1, earnings: 39),
        ]
    }
}
