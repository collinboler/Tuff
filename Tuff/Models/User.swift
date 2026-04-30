import Foundation
import SwiftUI

/// Payment provider the user prefers to be paid through after a league.
/// Stored on the user doc as the raw `id` string so it survives schema changes.
enum PaymentMethod: String, CaseIterable, Identifiable, Hashable {
    case none
    case venmo
    case zelle
    case cashapp
    case paypal
    case other

    var id: String { rawValue }

    /// Human-readable label shown in the picker / profile.
    var displayName: String {
        switch self {
        case .none:    return "None"
        case .venmo:   return "Venmo"
        case .zelle:   return "Zelle"
        case .cashapp: return "Cash App"
        case .paypal:  return "PayPal"
        case .other:   return "Other"
        }
    }

    /// Placeholder hint for the Payment ID field, tailored per provider.
    var idPlaceholder: String {
        switch self {
        case .none:    return ""
        case .venmo:   return "username"
        case .zelle:   return "phone or email"
        case .cashapp: return "cashtag"
        case .paypal:  return "paypal.me handle or email"
        case .other:   return "payment details"
        }
    }

    /// Render the user's payment ID for display (e.g. Venmo handles get a `@` prefix).
    func formattedID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        switch self {
        case .venmo, .cashapp:
            return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
        default:
            return trimmed
        }
    }

    /// Sanitize input as the user types — Venmo/Cash App should never store
    /// duplicate `@` prefixes; Zelle should keep digits + `+` for phone numbers.
    func sanitize(_ raw: String) -> String {
        switch self {
        case .venmo, .cashapp:
            var s = raw
            while s.hasPrefix("@") { s.removeFirst() }
            return s.trimmingCharacters(in: .whitespaces)
        default:
            return raw.trimmingCharacters(in: .whitespaces)
        }
    }
}

struct TuffUser: Identifiable, Hashable {
    let id: UUID
    var uid: String         // Firebase uid
    var name: String
    var username: String
    var imageName: String
    var photoURL: String?   // Firebase Storage download URL
    var isCurrentUser: Bool
    var screenTimeMinutes: Int
    var totalLeagues: Int
    var leaguesWon: Int
    var totalEarnings: Double
    var paymentMethod: PaymentMethod
    var paymentID: String

    /// Display string for "how do I pay this person" — falls back to `@username`
    /// so payouts always have something to show.
    var paymentDisplay: String {
        let formatted = paymentMethod.formattedID(paymentID)
        if !formatted.isEmpty {
            return "\(paymentMethod.displayName): \(formatted)"
        }
        if !username.isEmpty {
            return "@\(username)"
        }
        return name
    }

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
                 photoURL: nil, isCurrentUser: true, screenTimeMinutes: 0,
                 totalLeagues: 0, leaguesWon: 0, totalEarnings: 0,
                 paymentMethod: .none, paymentID: "")
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
    var todayBoughtCents: Int // virtual cents spent today in this league
    var isDQ: Bool          // left the league mid-season — score counts toward pool but can't win
    var joinedAt: Date?     // when this member joined the league

    init(id: UUID, user: TuffUser, currentScreenTime: TimeInterval,
         rank: Int, lastUpdated: Date, boughtCents: Int = 0, boughtMinutes: Int = 0,
         todayBoughtCents: Int = 0, isDQ: Bool = false, joinedAt: Date? = nil) {
        self.id = id
        self.user = user
        self.currentScreenTime = currentScreenTime
        self.rank = rank
        self.lastUpdated = lastUpdated
        self.boughtCents = boughtCents
        self.boughtMinutes = boughtMinutes
        self.todayBoughtCents = todayBoughtCents
        self.isDQ = isDQ
        self.joinedAt = joinedAt
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
