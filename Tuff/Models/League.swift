import Foundation

struct League: Identifiable {
    let id: UUID
    var name: String
    var key: String
    var startDate: Date
    var endDate: Date
    var potAmount: Double
    var costPerPerson: Double
    var isActive: Bool

    var members: [LeagueMember] {
        let users = TuffUser.users(forLeague: key)
        return users.enumerated().map { i, user in
            LeagueMember(
                id: user.id,
                user: user,
                currentScreenTime: Double(user.screenTimeMinutes * 60),
                rank: i + 1,
                lastUpdated: Date()
            )
        }
    }

    var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    var payoutBreakdown: [(place: String, amount: Double)] {
        [
            ("1st Place", potAmount * 0.50),
            ("2nd Place", potAmount * 0.30),
            ("3rd Place", potAmount * 0.20)
        ]
    }

    var sortedMembers: [LeagueMember] {
        members
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
        if earnings >= 0 {
            return "+$\(Int(earnings))"
        }
        return "-$\(Int(abs(earnings)))"
    }
}

extension League {
    static func makeSampleDate(month: Int, day: Int, year: Int = 2026) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components) ?? Date()
    }

    static var sampleLeagues: [League] {
        [
            League(
                id: UUID(),
                name: "Tiger Inn",
                key: "tiger",
                startDate: makeSampleDate(month: 3, day: 1),
                endDate: makeSampleDate(month: 3, day: 7),
                potAmount: 78,
                costPerPerson: 1,
                isActive: true
            ),
            League(
                id: UUID(),
                name: "Work Squad",
                key: "work",
                startDate: makeSampleDate(month: 3, day: 1),
                endDate: makeSampleDate(month: 3, day: 31),
                potAmount: 50,
                costPerPerson: 5,
                isActive: true
            ),
            League(
                id: UUID(),
                name: "Fam Bam",
                key: "fam",
                startDate: makeSampleDate(month: 2, day: 24),
                endDate: makeSampleDate(month: 3, day: 2),
                potAmount: 30,
                costPerPerson: 10,
                isActive: true
            )
        ]
    }
}

extension LeagueHistoryEntry {
    static var sampleHistory: [LeagueHistoryEntry] {
        [
            LeagueHistoryEntry(id: UUID(), leagueName: "Frosh Floor",
                startDate: League.makeSampleDate(month: 2, day: 17),
                endDate: League.makeSampleDate(month: 2, day: 23),
                placement: 1, earnings: 45),
            LeagueHistoryEntry(id: UUID(), leagueName: "Winter Break",
                startDate: League.makeSampleDate(month: 12, day: 20, year: 2025),
                endDate: League.makeSampleDate(month: 1, day: 2),
                placement: 2, earnings: 28),
            LeagueHistoryEntry(id: UUID(), leagueName: "Work Squad",
                startDate: League.makeSampleDate(month: 2, day: 1),
                endDate: League.makeSampleDate(month: 2, day: 28),
                placement: 4, earnings: -5),
            LeagueHistoryEntry(id: UUID(), leagueName: "Tiger Inn",
                startDate: League.makeSampleDate(month: 1, day: 20),
                endDate: League.makeSampleDate(month: 1, day: 26),
                placement: 1, earnings: 39),
            LeagueHistoryEntry(id: UUID(), leagueName: "Fam Bam",
                startDate: League.makeSampleDate(month: 1, day: 1),
                endDate: League.makeSampleDate(month: 1, day: 7),
                placement: 3, earnings: -10),
            LeagueHistoryEntry(id: UUID(), leagueName: "New Year Challenge",
                startDate: League.makeSampleDate(month: 1, day: 1),
                endDate: League.makeSampleDate(month: 1, day: 14),
                placement: 1, earnings: 36),
        ]
    }
}
