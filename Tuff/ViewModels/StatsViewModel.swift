import Foundation
import Combine

@MainActor
class StatsViewModel: ObservableObject {
    enum TimePeriod: String, CaseIterable {
        case sevenDays = "7D"
        case thirtyDays = "30D"

        var days: Int {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            }
        }
    }

    @Published var selectedPeriod: TimePeriod = .sevenDays {
        didSet { recomputeStats() }
    }
    @Published var weeklyData: [DailyScreenTime] = DailyScreenTime.sampleWeek
    @Published var monthlyData: [DailyScreenTime] = DailyScreenTime.sampleMonth
    @Published var stats: ScreenTimeStats = DailyScreenTime.sampleStats

    private let screenTimeManager = ScreenTimeManager.shared

    var displayData: [DailyScreenTime] {
        switch selectedPeriod {
        case .sevenDays: return weeklyData
        case .thirtyDays: return monthlyData
        }
    }

    func refreshData() async {
        weeklyData = screenTimeManager.fetchWeeklyData()
        monthlyData = screenTimeManager.fetchMonthlyData()
        recomputeStats()
    }

    private func recomputeStats() {
        stats = screenTimeManager.fetchStats(for: selectedPeriod.days)
    }
}
