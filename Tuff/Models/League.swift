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
    /// Bundle IDs of apps that are always allowed (kept for backwards-compat display).
    var allowedApps: [String]
    /// Number of apps the creator has marked as always allowed (shown to members).
    var allowedAppsCount: Int

    /// Total virtual pool = sum of all members' boughtCents (including DQ'd).
    var poolCents: Int { members.reduce(0) { $0 + $1.boughtCents } }
    var poolDollars: Double { Double(poolCents) / 100.0 }

    var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    /// Winner takes all — person with lowest boughtCents (non-DQ) wins the pool.
    var payoutBreakdown: [(place: String, amount: String)] {
        let eligible = members.filter { !$0.isDQ }
        let note = eligible.isEmpty ? "" : " (DQ'd members ineligible)"
        return [("1st Place — Lowest spent wins\(note)", String(format: "$%.2f pool", poolDollars))]
    }

    /// Active members first (sorted by boughtCents ascending), DQ'd members at the bottom.
    var sortedMembers: [LeagueMember] {
        let active = members.filter { !$0.isDQ }.sorted { $0.boughtCents < $1.boughtCents }
        let disqualified = members.filter { $0.isDQ }.sorted { $0.boughtCents < $1.boughtCents }
        return active + disqualified
    }

    /// True if the member joined after 20% of the league's duration had elapsed.
    func isLateJoiner(_ member: LeagueMember) -> Bool {
        guard let joinedAt = member.joinedAt else { return false }
        let totalDuration = endDate.timeIntervalSince(startDate)
        guard totalDuration > 0 else { return false }
        let threshold = startDate.addingTimeInterval(totalDuration * 0.20)
        return joinedAt > threshold
    }

    // MARK: - Firestore parsing

    static func from(_ data: [String: Any], id: String) -> League? {
        guard let name = data["name"] as? String,
              let startTs = data["startDate"] as? Timestamp,
              let endTs = data["endDate"] as? Timestamp else { return nil }

        let currentUID = Auth.auth().currentUser?.uid ?? ""

        // ledger is a top-level map { uid: { boughtCents: Int, boughtMinutes: Int } }
        // This allows atomic FieldValue.increment updates without transactions.
        let ledger = data["ledger"] as? [String: [String: Any]] ?? [:]
        let dailyLedger = data["dailyLedger"] as? [String: Any] ?? [:]
        let todayLedger = dailyLedger[dayKey(for: Date())] as? [String: Any] ?? [:]
        let dqdUids = Set(data["dqdUids"] as? [String] ?? [])

        func intValue(_ any: Any?) -> Int {
            if let v = any as? Int { return v }
            if let v = any as? Int64 { return Int(v) }
            if let v = any as? NSNumber { return v.intValue }
            return 0
        }

        let memberProfiles = data["memberProfiles"] as? [[String: Any]] ?? []
        let members: [LeagueMember] = memberProfiles.enumerated().map { i, profile in
            let uid = profile["uid"] as? String ?? ""
            let entry = ledger[uid] ?? [:]
            let todayEntry = todayLedger[uid] as? [String: Any] ?? [:]
            let memberUser = TuffUser(
                id: UUID(),
                uid: uid,
                name: profile["name"] as? String ?? "Unknown",
                username: profile["username"] as? String ?? "",
                imageName: "",
                photoURL: profile["photoURL"] as? String,
                isCurrentUser: uid == currentUID,
                screenTimeMinutes: profile["screenTimeMinutes"] as? Int ?? 0,
                totalLeagues: 0,
                leaguesWon: 0,
                totalEarnings: 0
            )
            let joinedAt = (profile["joinedAt"] as? Timestamp)?.dateValue()
            return LeagueMember(
                id: UUID(),
                user: memberUser,
                currentScreenTime: Double((profile["screenTimeMinutes"] as? Int ?? 0) * 60),
                rank: i + 1,
                lastUpdated: Date(),
                boughtCents: intValue(entry["boughtCents"]),
                boughtMinutes: intValue(entry["boughtMinutes"]),
                todayBoughtCents: intValue(todayEntry["boughtCents"]),
                isDQ: dqdUids.contains(uid),
                joinedAt: joinedAt
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
            members: members,
            allowedApps: data["allowedApps"] as? [String] ?? [],
            allowedAppsCount: intValue(data["allowedAppsCount"])
        )
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}

// MARK: - Allowed App Suggestions

struct AllowedApp: Identifiable {
    let id: String        // bundle ID stored in Firestore
    let displayName: String
    let icon: String      // SF Symbol name

    static let suggestions: [AllowedApp] = [
        AllowedApp(id: "com.apple.MobileSMS",       displayName: "Messages",   icon: "message.fill"),
        AllowedApp(id: "com.apple.mobilephone",     displayName: "Phone",      icon: "phone.fill"),
        AllowedApp(id: "com.apple.mobileslideshow", displayName: "Photos",     icon: "photo.fill"),
        AllowedApp(id: "com.apple.Music",           displayName: "Music",      icon: "music.note"),
        AllowedApp(id: "com.apple.Maps",            displayName: "Maps",       icon: "map.fill"),
        AllowedApp(id: "com.apple.facetime",        displayName: "FaceTime",   icon: "video.fill"),
        AllowedApp(id: "com.apple.camera",          displayName: "Camera",     icon: "camera.fill"),
        AllowedApp(id: "com.apple.Preferences",     displayName: "Settings",   icon: "gearshape.fill"),
        AllowedApp(id: "com.apple.calculator",      displayName: "Calculator", icon: "plus.slash.minus"),
        AllowedApp(id: "com.apple.mobilenotes",     displayName: "Notes",      icon: "note.text"),
    ]

    static func match(bundleID: String) -> AllowedApp? {
        suggestions.first { $0.id == bundleID }
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
