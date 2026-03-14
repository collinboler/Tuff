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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                topBar
                statsContent
            }
            .padding(.bottom, 80)
        }
        .background(Color.white)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text("YOUR STATS")
                .font(TuffFonts.pageTitle())
                .foregroundColor(.black)
                .tracking(0.06 * 26)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    private var statsContent: some View {
        VStack(spacing: 14) {
            #if !targetEnvironment(simulator)
            DeviceActivityReport(
                DeviceActivityReport.Context("TuffDailyActivity"),
                filter: reportFilter
            )
            .frame(minHeight: 860)
            #endif
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    StatsView()
        .environmentObject(ScreenTimeManager.shared)
}
