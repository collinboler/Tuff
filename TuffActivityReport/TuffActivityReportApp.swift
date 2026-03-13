import DeviceActivity
import SwiftUI

@main
@MainActor
struct TuffActivityReportApp: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TuffDailyReportScene { totalScreenTime in
            TuffDailyReportView(totalScreenTime: totalScreenTime)
        }
    }
}
