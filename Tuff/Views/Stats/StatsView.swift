import SwiftUI
import DeviceActivity

struct StatsView: View {
    @EnvironmentObject var screenTimeManager: ScreenTimeManager

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
                filter: DeviceActivityFilter(
                    segment: .daily(
                        during: DateInterval(
                            start: Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -29, to: Date())!),
                            end: Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
                        )
                    )
                )
            )
            .frame(minHeight: 750)
            #endif

            streakCard
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 32))
                .foregroundColor(TuffColors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("STREAK")
                    .font(TuffFonts.streakLabel())
                    .foregroundColor(.white)
                Text("Keep going — check back tomorrow!")
                    .font(TuffFonts.caption(11))
                    .foregroundColor(TuffColors.textSecondary)
            }
            Spacer()
        }
        .padding(18)
        .background(TuffColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    StatsView()
        .environmentObject(ScreenTimeManager.shared)
}
