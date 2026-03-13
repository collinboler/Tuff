import Foundation
import SwiftUI

struct TuffUser: Identifiable, Hashable {
    let id: UUID
    var name: String
    var username: String
    var imageName: String
    var isCurrentUser: Bool
    var screenTimeMinutes: Int
    var leagueKeys: [String]
    var totalLeagues: Int
    var leaguesWon: Int
    var totalEarnings: Double

    var formattedScreenTime: String {
        let h = screenTimeMinutes / 60
        let m = screenTimeMinutes % 60
        return "\(h)h \(String(format: "%02d", m))m"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TuffUser, rhs: TuffUser) -> Bool {
        lhs.id == rhs.id
    }
}

struct LeagueMember: Identifiable {
    let id: UUID
    let user: TuffUser
    var currentScreenTime: TimeInterval
    var rank: Int
    var lastUpdated: Date

    var screenTimeMinutes: Int {
        Int(currentScreenTime) / 60
    }

    var formattedScreenTime: String {
        let h = screenTimeMinutes / 60
        let m = screenTimeMinutes % 60
        return "\(h)h \(String(format: "%02d", m))m"
    }

    var lastUpdatedText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(lastUpdated) {
            return "Today \(formattedScreenTime)"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: lastUpdated)) \(formattedScreenTime)"
    }
}

// MARK: - Roster (matches HTML mockup's users.js exactly)

extension TuffUser {
    static let allUsers: [TuffUser] = [
        TuffUser(id: UUID(), name: "Rhodes",        username: "rhodes",   imageName: "Rhodes",        isCurrentUser: false, screenTimeMinutes: 62,  leagueKeys: ["tiger","work"], totalLeagues: 8, leaguesWon: 3, totalEarnings: 95),
        TuffUser(id: UUID(), name: "Ava",           username: "ava",      imageName: "Ava",           isCurrentUser: false, screenTimeMinutes: 88,  leagueKeys: ["tiger"], totalLeagues: 6, leaguesWon: 2, totalEarnings: 60),
        TuffUser(id: UUID(), name: "Evan",          username: "evan",     imageName: "Evan",          isCurrentUser: false, screenTimeMinutes: 105, leagueKeys: ["work","tiger"], totalLeagues: 7, leaguesWon: 2, totalEarnings: 40),
        TuffUser(id: UUID(), name: "JP",            username: "jp",       imageName: "JP",            isCurrentUser: false, screenTimeMinutes: 122, leagueKeys: ["tiger"], totalLeagues: 5, leaguesWon: 1, totalEarnings: 20),
        TuffUser(id: UUID(), name: "Sarah",         username: "sarah",    imageName: "Sarah",         isCurrentUser: false, screenTimeMinutes: 138, leagueKeys: ["work","fam"], totalLeagues: 10, leaguesWon: 5, totalEarnings: 120),
        TuffUser(id: UUID(), name: "Yusuf",         username: "yusuf",    imageName: "Yusuf",         isCurrentUser: false, screenTimeMinutes: 151, leagueKeys: ["work"], totalLeagues: 7, leaguesWon: 1, totalEarnings: 30),
        TuffUser(id: UUID(), name: "Katie Choi",    username: "katie",    imageName: "Katie",         isCurrentUser: true,  screenTimeMinutes: 157, leagueKeys: ["tiger","work","fam"], totalLeagues: 12, leaguesWon: 4, totalEarnings: 148),
        TuffUser(id: UUID(), name: "Oliver",        username: "oliver",   imageName: "Oliver",        isCurrentUser: false, screenTimeMinutes: 174, leagueKeys: ["tiger"], totalLeagues: 4, leaguesWon: 0, totalEarnings: -5),
        TuffUser(id: UUID(), name: "James IV",      username: "jamesiv",  imageName: "James_IV",      isCurrentUser: false, screenTimeMinutes: 191, leagueKeys: ["work"], totalLeagues: 5, leaguesWon: 2, totalEarnings: 55),
        TuffUser(id: UUID(), name: "Chaemin",       username: "chaemin",  imageName: "Chaemin",       isCurrentUser: false, screenTimeMinutes: 208, leagueKeys: ["fam"], totalLeagues: 3, leaguesWon: 0, totalEarnings: -15),
        TuffUser(id: UUID(), name: "Ivy Chen",      username: "ivychen",  imageName: "Ivy_Chen",      isCurrentUser: false, screenTimeMinutes: 224, leagueKeys: ["work","tiger"], totalLeagues: 9, leaguesWon: 3, totalEarnings: 85),
        TuffUser(id: UUID(), name: "Jon",           username: "jon",      imageName: "Jon",           isCurrentUser: false, screenTimeMinutes: 241, leagueKeys: ["work"], totalLeagues: 4, leaguesWon: 0, totalEarnings: -20),
        TuffUser(id: UUID(), name: "Yansen Looker", username: "yansen",   imageName: "Yansen_Looker", isCurrentUser: false, screenTimeMinutes: 258, leagueKeys: ["fam"], totalLeagues: 6, leaguesWon: 1, totalEarnings: 15),
        TuffUser(id: UUID(), name: "Zachary",       username: "zachary",  imageName: "Zachary",       isCurrentUser: false, screenTimeMinutes: 277, leagueKeys: ["work"], totalLeagues: 6, leaguesWon: 1, totalEarnings: 10),
        TuffUser(id: UUID(), name: "Sawooly",       username: "sawooly",  imageName: "Sawooly",       isCurrentUser: false, screenTimeMinutes: 298, leagueKeys: ["tiger","fam"], totalLeagues: 3, leaguesWon: 0, totalEarnings: -10),
        TuffUser(id: UUID(), name: "B Clark",       username: "bclark",   imageName: "B_Clark",       isCurrentUser: false, screenTimeMinutes: 321, leagueKeys: ["work"], totalLeagues: 3, leaguesWon: 0, totalEarnings: -25),
        TuffUser(id: UUID(), name: "Collin",        username: "collin",   imageName: "Collin",        isCurrentUser: false, screenTimeMinutes: 398, leagueKeys: ["work","fam"], totalLeagues: 5, leaguesWon: 1, totalEarnings: 25),
        TuffUser(id: UUID(), name: "Brian",         username: "brian",    imageName: "Brian",         isCurrentUser: false, screenTimeMinutes: 432, leagueKeys: ["tiger","fam"], totalLeagues: 4, leaguesWon: 0, totalEarnings: -30),
    ]

    static var currentUser: TuffUser {
        allUsers.first(where: { $0.isCurrentUser })!
    }

    static func users(forLeague key: String) -> [TuffUser] {
        allUsers.filter { $0.leagueKeys.contains(key) }
            .sorted { $0.screenTimeMinutes < $1.screenTimeMinutes }
    }
}
