import DeviceActivity
import SwiftUI
import Foundation

extension DeviceActivityReport.Context {
    static let dailyActivity = Self("TuffDailyActivity")
}

struct ReportConfig: Codable {
    let todayFormatted: String
    let dailyTotals: [DayEntry]

    struct DayEntry: Codable {
        let date: Date
        let totalSeconds: TimeInterval
    }
}

struct TuffDailyReportScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .dailyActivity

    let content: (String) -> TuffDailyReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> String {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        var dayTotals: [Date: TimeInterval] = [:]

        for await activityData in data {
            for await segment in activityData.activitySegments {
                let segmentDay = calendar.startOfDay(for: segment.dateInterval.start)
                dayTotals[segmentDay, default: 0] += segment.totalActivityDuration
            }
        }

        let entries = dayTotals
            .map { ReportConfig.DayEntry(date: $0.key, totalSeconds: $0.value) }
            .sorted { $0.date < $1.date }

        if let defaults = UserDefaults(suiteName: "group.com.collinboler.tuff"),
           let encoded = try? JSONEncoder().encode(entries) {
            defaults.set(encoded, forKey: "realDailyHistory")
            defaults.set(Date(), forKey: "realDataLastUpdated")
        }

        let todayTotal = dayTotals[todayStart] ?? 0

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading

        return formatter.string(from: todayTotal) ?? "0m"
    }
}
