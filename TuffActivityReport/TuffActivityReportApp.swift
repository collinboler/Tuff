import DeviceActivity
import SwiftUI

@main
@MainActor
struct TuffActivityReportApp: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TuffDailyReportScene { reportData in
            TuffDailyReportView(data: reportData)
        }
    }
}
