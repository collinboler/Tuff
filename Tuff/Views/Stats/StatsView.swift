import SwiftUI
import DeviceActivity

struct StatsView: View {
    @EnvironmentObject var screenTimeManager: ScreenTimeManager

    private let reportFilter: DeviceActivityFilter = {
        let calendar = Calendar.current
        let todayEnd = calendar.startOfDay(for: Date()).addingTimeInterval(86400)
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: Date())!)
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: todayEnd))
        )
    }()

    var body: some View {
        Group {
            #if !targetEnvironment(simulator)
            DeviceActivityReport(
                DeviceActivityReport.Context("TuffDailyActivity"),
                filter: reportFilter
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            #endif
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }
}

#Preview {
    StatsView()
        .environmentObject(ScreenTimeManager.shared)
}
