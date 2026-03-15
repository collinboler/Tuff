import DeviceActivity
import SwiftUI

@main
struct TuffActivityReportApp: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TuffDailyReportScene { reportData in
            TuffDailyReportView(data: reportData)
        }
    }
}
