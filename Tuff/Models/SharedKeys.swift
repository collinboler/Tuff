import Foundation

/// Keys for data shared between the main app and extensions via App Group UserDefaults.
/// App Group ID: group.com.collinboler.tuff
enum TuffSharedKeys {
    static let appGroupID = "group.com.collinboler.tuff"

    // Today's total screen time in seconds
    static let todayScreenTime = "todayScreenTime"
    // Last time the extension updated the data
    static let lastUpdated = "screenTimeLastUpdated"
    // Daily screen time history: encoded [DailyRecord]
    static let dailyHistory = "dailyScreenTimeHistory"
    // Per-app breakdown for today: encoded [AppRecord]
    static let appBreakdown = "appBreakdownToday"
}

/// Lightweight codable record stored in App Group UserDefaults.
struct DailyRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let totalSeconds: TimeInterval
    let appBreakdown: [AppRecord]

    var hours: Double { totalSeconds / 3600 }

    var formattedTime: String {
        let h = Int(totalSeconds) / 3600
        let m = (Int(totalSeconds) % 3600) / 60
        return "\(h)h \(String(format: "%02d", m))m"
    }

    var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

struct AppRecord: Codable, Identifiable {
    let id: UUID
    let bundleID: String
    let displayName: String
    let totalSeconds: TimeInterval
    let categoryName: String
}

/// Shared UserDefaults bridge between app and extensions.
struct TuffSharedStore {
    static var defaults: UserDefaults? {
        UserDefaults(suiteName: TuffSharedKeys.appGroupID)
    }

    static func saveTodayScreenTime(_ seconds: TimeInterval) {
        defaults?.set(seconds, forKey: TuffSharedKeys.todayScreenTime)
        defaults?.set(Date(), forKey: TuffSharedKeys.lastUpdated)
    }

    static func todayScreenTime() -> TimeInterval? {
        let val = defaults?.double(forKey: TuffSharedKeys.todayScreenTime) ?? 0
        return val > 0 ? val : nil
    }

    static func lastUpdated() -> Date? {
        defaults?.object(forKey: TuffSharedKeys.lastUpdated) as? Date
    }

    static func saveDailyHistory(_ records: [DailyRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            defaults?.set(data, forKey: TuffSharedKeys.dailyHistory)
        }
    }

    static func dailyHistory() -> [DailyRecord] {
        guard let data = defaults?.data(forKey: TuffSharedKeys.dailyHistory),
              let records = try? JSONDecoder().decode([DailyRecord].self, from: data) else {
            return []
        }
        return records
    }

    static func saveAppBreakdown(_ records: [AppRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            defaults?.set(data, forKey: TuffSharedKeys.appBreakdown)
        }
    }

    static func appBreakdown() -> [AppRecord] {
        guard let data = defaults?.data(forKey: TuffSharedKeys.appBreakdown),
              let records = try? JSONDecoder().decode([AppRecord].self, from: data) else {
            return []
        }
        return records
    }
}
