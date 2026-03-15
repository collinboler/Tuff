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
