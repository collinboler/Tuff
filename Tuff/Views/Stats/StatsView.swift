import SwiftUI
import DeviceActivity

extension DeviceActivityReport.Context {
    static let dailyActivity = Self("TuffDailyActivity")
}

struct StatsView: View {
    @StateObject private var viewModel = StatsViewModel()
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
        .task {
            await viewModel.refreshData()
        }
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
                            start: Calendar.current.startOfDay(for: Date()),
                            end: Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
                        )
                    )
                )
            )
            .frame(height: 100)
            #endif

            HStack {
                Spacer()
                periodToggle
            }

            chartCard

            // Stat boxes
            HStack(spacing: 8) {
                statBlock(label: "Daily Avg", value: viewModel.stats.formattedAverage, isAccent: true)
                statBlock(label: "Best Day", value: viewModel.stats.formattedBest, isAccent: false)
                statBlock(label: "Worst Day", value: viewModel.stats.formattedWorst, isAccent: false)
            }

            streakCard
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        ScreenTimeChartView(
            data: viewModel.displayData,
            period: viewModel.selectedPeriod
        )
        .frame(height: 140)
        .padding(16)
        .background(TuffColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Period Toggle

    private var periodToggle: some View {
        HStack(spacing: 0) {
            ForEach(StatsViewModel.TimePeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedPeriod = period
                    }
                } label: {
                    Text(period.rawValue)
                        .font(TuffFonts.togglePill())
                        .foregroundColor(viewModel.selectedPeriod == period ? .white : TuffColors.textSecondary)
                        .tracking(0.06 * 12)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(viewModel.selectedPeriod == period ? TuffColors.accent : Color.clear)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(2)
        .background(Color.white)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(TuffColors.divider, lineWidth: 1))
    }

    private func statBlock(label: String, value: String, isAccent: Bool) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(TuffFonts.statLabel())
                .foregroundColor(.gray)
                .tracking(0.1 * 10)
            Text(value)
                .font(TuffFonts.statValue())
                .foregroundColor(isAccent ? TuffColors.accent : .white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(TuffColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        HStack(spacing: 16) {
            Text("\(viewModel.stats.currentStreak)")
                .font(TuffFonts.streakNumber())
                .foregroundColor(TuffColors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("DAY STREAK")
                    .font(TuffFonts.streakLabel())
                    .foregroundColor(.white)
                Text("Under your \(viewModel.stats.formattedGoal) daily goal")
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
