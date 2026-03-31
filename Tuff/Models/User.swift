import Foundation
import SwiftUI

struct TuffUser: Identifiable, Hashable {
    let id: UUID
    var uid: String         // Firebase uid
    var name: String
    var username: String
    var imageName: String
    var isCurrentUser: Bool
    var screenTimeMinutes: Int
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

    static var currentUser: TuffUser {
        TuffUser(id: UUID(), uid: "", name: "", username: "", imageName: "",
                 isCurrentUser: true, screenTimeMinutes: 0,
                 totalLeagues: 0, leaguesWon: 0, totalEarnings: 0)
    }
}

struct LeagueMember: Identifiable {
    let id: UUID
    let user: TuffUser
    var currentScreenTime: TimeInterval
    var rank: Int
    var lastUpdated: Date
    var boughtCents: Int    // total virtual cents spent on breaks in this league
    var boughtMinutes: Int  // total minutes of breaks purchased
    var isDQ: Bool          // left the league mid-season — score counts toward pool but can't win

    init(id: UUID, user: TuffUser, currentScreenTime: TimeInterval,
         rank: Int, lastUpdated: Date, boughtCents: Int = 0, boughtMinutes: Int = 0, isDQ: Bool = false) {
        self.id = id
        self.user = user
        self.currentScreenTime = currentScreenTime
        self.rank = rank
        self.lastUpdated = lastUpdated
        self.boughtCents = boughtCents
        self.boughtMinutes = boughtMinutes
        self.isDQ = isDQ
    }

    var screenTimeMinutes: Int { Int(currentScreenTime) / 60 }

    var formattedScreenTime: String {
        let h = screenTimeMinutes / 60
        let m = screenTimeMinutes % 60
        return "\(h)h \(String(format: "%02d", m))m"
    }

    var formattedBoughtTime: String {
        if boughtMinutes == 0 { return "0m bought" }
        let h = boughtMinutes / 60
        let m = boughtMinutes % 60
        if h > 0 { return "\(h)h \(m)m bought" }
        return "\(m)m bought"
    }

    var formattedBoughtCost: String {
        if boughtCents == 0 { return "$0.00" }
        return String(format: "$%.2f", Double(boughtCents) / 100.0)
    }

    var lastUpdatedText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(lastUpdated) {
            return "Updated today"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Updated \(formatter.string(from: lastUpdated))"
    }
}
