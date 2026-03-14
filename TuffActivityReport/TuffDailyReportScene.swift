import DeviceActivity
import ManagedSettings
import SwiftUI
import Foundation

extension DeviceActivityReport.Context {
    static let dailyActivity = Self("TuffDailyActivity")
}

struct ReportData {
    let todayFormatted: String
    let days: [DayData]

    struct DayData: Identifiable {
        let id = UUID()
        let date: Date
        let totalSeconds: TimeInterval
        let apps: [AppEntry]

        var hours: Double { totalSeconds / 3600.0 }
    }

    struct AppEntry: Identifiable {
        let id = UUID()
        let application: Application
        let seconds: TimeInterval
    }
}

struct TuffDailyReportScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .dailyActivity

    let content: (ReportData) -> TuffDailyReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ReportData {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        var dayMap: [Date: (total: TimeInterval, apps: [Application: TimeInterval])] = [:]

        for await activityData in data {
            for await segment in activityData.activitySegments {
                let segmentDay = calendar.startOfDay(for: segment.dateInterval.start)
                var entry = dayMap[segmentDay] ?? (total: 0, apps: [:])
                entry.total = max(entry.total, segment.totalActivityDuration)

                for await categoryActivity in segment.categories {
                    for await appActivity in categoryActivity.applications {
                        let app = appActivity.application
                        let dur = appActivity.totalActivityDuration
                        entry.apps[app] = max(entry.apps[app] ?? 0, dur)
                    }
                }
                dayMap[segmentDay] = entry
            }
        }

        // Ensure today always has an entry even if no segment was keyed to it
        let todayTotal = dayMap[todayStart]?.total
            ?? dayMap.first(where: { calendar.isDate($0.key, inSameDayAs: todayStart) })?.value.total
            ?? 0
        if dayMap[todayStart] == nil {
            dayMap[todayStart] = (total: todayTotal, apps: [:])
        }

        let days = dayMap
            .sorted { $0.key < $1.key }
            .map { date, info in
                let sortedApps = info.apps
                    .sorted { $0.value > $1.value }
                    .prefix(8)
                    .map { ReportData.AppEntry(application: $0.key, seconds: $0.value) }
                return ReportData.DayData(
                    date: date,
                    totalSeconds: info.total,
                    apps: Array(sortedApps)
                )
            }

        return ReportData(
            todayFormatted: formatTime(todayTotal),
            days: days
        )
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h == 0 && m == 0 { return "0m" }
        if h == 0 { return "\(m)m" }
        return "\(h)h \(String(format: "%02d", m))m"
    }
}
