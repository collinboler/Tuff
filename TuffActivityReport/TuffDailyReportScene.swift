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

        var totalSegments = 0
        var totalCategories = 0
        var totalApps = 0

        do {
            for await activityData in data {
                for await segment in activityData.activitySegments {
                    totalSegments += 1
                    let segmentDay = calendar.startOfDay(for: segment.dateInterval.start)
                    var entry = dayMap[segmentDay] ?? (total: 0, apps: [:])
                    entry.total += segment.totalActivityDuration

                    var catsInSegment = 0
                    var appsInSegment = 0
                    for await categoryActivity in segment.categories {
                        catsInSegment += 1
                        totalCategories += 1
                        for await appActivity in categoryActivity.applications {
                            appsInSegment += 1
                            totalApps += 1
                            let app = appActivity.application
                            let dur = appActivity.totalActivityDuration
                            guard let token = app.token else { continue }
                            let existing = entry.apps[token]?.seconds ?? 0
                            entry.apps[token] = (application: app, seconds: existing + dur)
                        }
                    }
                    let fmt = DateFormatter(); fmt.dateFormat = "MM-dd"
                    print("[TuffReport] segment \(fmt.string(from: segmentDay)) total=\(Int(segment.totalActivityDuration/60))m cats=\(catsInSegment) apps=\(appsInSegment)")
                    dayMap[segmentDay] = entry
                }
            }
        } catch {
            print("[TuffReport] data iteration error: \(error)")
        }
        print("[TuffReport] DONE segments=\(totalSegments) categories=\(totalCategories) apps=\(totalApps) days=\(dayMap.count)")

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

        // Write history to shared app group so the main app can read today's total.
        let reportRecords = days.map { day -> DailyRecord in
            let breakdown = day.apps.map { entry in
                AppRecord(
                    id: UUID(),
                    bundleID: entry.bundleID ?? "",
                    displayName: entry.application.localizedDisplayName ?? entry.bundleID ?? "Unknown",
                    totalSeconds: entry.seconds,
                    categoryName: ""
                )
            }
            return DailyRecord(id: UUID(), date: day.date, totalSeconds: day.totalSeconds, appBreakdown: breakdown)
        }
        let reportDates = Set(reportRecords.map { Calendar.current.startOfDay(for: $0.date) })
        let existing = TuffSharedStore.dailyHistory()
        let preserved = existing.filter { !reportDates.contains(Calendar.current.startOfDay(for: $0.date)) }
        let mergedRecords = reportRecords.map { newRecord -> DailyRecord in
            let dayStart = Calendar.current.startOfDay(for: newRecord.date)
            if newRecord.appBreakdown.isEmpty,
               let oldRecord = existing.first(where: { Calendar.current.isDate($0.date, inSameDayAs: dayStart) }),
               !oldRecord.appBreakdown.isEmpty {
                return DailyRecord(id: newRecord.id, date: newRecord.date,
                                   totalSeconds: newRecord.totalSeconds,
                                   appBreakdown: oldRecord.appBreakdown)
            }
            return newRecord
        }
        TuffSharedStore.saveDailyHistory(preserved + mergedRecords)

        if todayTotal > 0 {
            TuffSharedStore.saveTodayScreenTime(todayTotal)
        }

        if let todayRecord = reportRecords.first(where: { calendar.isDate($0.date, inSameDayAs: todayStart) }),
           !todayRecord.appBreakdown.isEmpty {
            TuffSharedStore.saveAppBreakdown(todayRecord.appBreakdown)
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
