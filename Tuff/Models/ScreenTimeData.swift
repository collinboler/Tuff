import Foundation

struct DailyScreenTime: Identifiable {
    let id = UUID()
    let date: Date
    let totalSeconds: TimeInterval
    let appBreakdown: [AppUsage]

    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    var hours: Double {
        totalSeconds / 3600.0
    }

    var formattedTime: String {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }
}

struct AppUsage: Identifiable {
    let id = UUID()
    let appName: String
    let bundleIdentifier: String
    let seconds: TimeInterval
    let category: AppCategory
}

enum AppCategory: String, CaseIterable, Codable {
    case social = "Social"
    case entertainment = "Entertainment"
    case productivity = "Productivity"
    case games = "Games"
    case education = "Education"
    case health = "Health"
    case utilities = "Utilities"
    case other = "Other"
}

struct ScreenTimeStats {
    let dailyAverage: TimeInterval
    let bestDay: TimeInterval
    let worstDay: TimeInterval
    let currentStreak: Int
    let dailyGoal: TimeInterval

    var formattedAverage: String { formatTime(dailyAverage) }
    var formattedBest: String { formatTime(bestDay) }
    var formattedWorst: String { formatTime(worstDay) }
    var formattedGoal: String { formatTime(dailyGoal) }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }
}

extension DailyScreenTime {
    static var sampleWeek: [DailyScreenTime] {
        let calendar = Calendar.current
        let today = Date()

        return (0..<7).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let screenTimes: [TimeInterval] = [9000, 7200, 10800, 8400, 10200, 6000, 7800]
            let seconds = screenTimes[6 - daysAgo]

            return DailyScreenTime(
                date: date,
                totalSeconds: seconds,
                appBreakdown: [
                    AppUsage(appName: "Instagram", bundleIdentifier: "com.instagram", seconds: seconds * 0.3, category: .social),
                    AppUsage(appName: "TikTok", bundleIdentifier: "com.tiktok", seconds: seconds * 0.25, category: .entertainment),
                    AppUsage(appName: "YouTube", bundleIdentifier: "com.youtube", seconds: seconds * 0.2, category: .entertainment),
                    AppUsage(appName: "Messages", bundleIdentifier: "com.apple.messages", seconds: seconds * 0.15, category: .social),
                    AppUsage(appName: "Safari", bundleIdentifier: "com.apple.safari", seconds: seconds * 0.1, category: .utilities),
                ]
            )
        }
    }

    static var sampleMonth: [DailyScreenTime] {
        let calendar = Calendar.current
        let today = Date()

        return (0..<30).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let base: TimeInterval = 8400
            let variance = Double.random(in: -3600...3600)
            let seconds = max(3600, base + variance)

            return DailyScreenTime(
                date: date,
                totalSeconds: seconds,
                appBreakdown: []
            )
        }
    }

    static var sampleStats: ScreenTimeStats {
        ScreenTimeStats(
            dailyAverage: 8940,
            bestDay: 3840,
            worstDay: 12600,
            currentStreak: 5,
            dailyGoal: 10800
        )
    }
}
