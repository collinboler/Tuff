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
            if !screenTimeManager.isAuthorized {
                screenTimeGate
            } else {
                #if !targetEnvironment(simulator)
                DeviceActivityReport(
                    DeviceActivityReport.Context("TuffDailyActivity"),
                    filter: reportFilter
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 20)
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }

    private var screenTimeGate: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hourglass.circle")
                .font(.system(size: 52))
                .foregroundColor(TuffColors.textSecondary)
            Text("Screen Time Not Granted")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.black)
            Text("Allow Screen Time access so Tuff can show your stats.")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                Task { await screenTimeManager.requestAuthorization() }
            } label: {
                Text("Allow Screen Time")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(TuffColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }
}

#Preview {
    StatsView()
        .environmentObject(ScreenTimeManager.shared)
}
