import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
    static let dailyActivity = Self("TuffDailyActivity")
}

struct TuffDailyReportScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .dailyActivity

    let content: (String) -> TuffDailyReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> String {
        var totalDuration: TimeInterval = 0

        for await activityData in data {
            var segments: [DeviceActivityData.ActivitySegment] = []
            for await segment in activityData.activitySegments {
                segments.append(segment)
            }
            totalDuration += segments.reduce(0) { $0 + $1.totalActivityDuration }
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading

        return formatter.string(from: totalDuration) ?? "0m"
    }
}
