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
        let bundleID: String?
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

        var dayMap: [Date: (total: TimeInterval, apps: [ApplicationToken: (application: Application, seconds: TimeInterval)])] = [:]

        for await activityData in data {
            for await segment in activityData.activitySegments {
                let segmentDay = calendar.startOfDay(for: segment.dateInterval.start)
                var entry = dayMap[segmentDay] ?? (total: 0, apps: [:])
                entry.total = max(entry.total, segment.totalActivityDuration)

                for await categoryActivity in segment.categories {
                    for await appActivity in categoryActivity.applications {
                        let app = appActivity.application
                        let dur = appActivity.totalActivityDuration
                        guard let token = app.token else { continue }
                        let existing = entry.apps[token]?.seconds ?? 0
                        entry.apps[token] = (application: app, seconds: max(existing, dur))
                    }
                }
                dayMap[segmentDay] = entry
            }
        }

        let fuzzyToday = dayMap.first(where: { calendar.isDate($0.key, inSameDayAs: todayStart) })
        let todayTotal = dayMap[todayStart]?.total ?? fuzzyToday?.value.total ?? 0
        if dayMap[todayStart] == nil {
            let todayApps = fuzzyToday?.value.apps ?? [:]
            dayMap[todayStart] = (total: todayTotal, apps: todayApps)
        }

        let days = dayMap
            .sorted { $0.key < $1.key }
            .map { date, info in
                let sortedApps = info.apps.values
                    .sorted { $0.seconds > $1.seconds }
                    .prefix(8)
                    .map { ReportData.AppEntry(application: $0.application, bundleID: $0.application.bundleIdentifier, seconds: $0.seconds) }
                return ReportData.DayData(
                    date: date,
                    totalSeconds: info.total,
                    apps: Array(sortedApps)
                )
            }

        // Write history to shared app group so the main app can read today's total
        let records = days.map {
            DailyRecord(id: UUID(), date: $0.date, totalSeconds: $0.totalSeconds, appBreakdown: [])
        }
        TuffSharedStore.saveDailyHistory(records)
        TuffSharedStore.saveTodayScreenTime(todayTotal)

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
