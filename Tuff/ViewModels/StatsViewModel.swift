import Foundation
import Combine

@MainActor
class StatsViewModel: ObservableObject {
    enum TimePeriod: String, CaseIterable {
        case sevenDays = "7D"
        case thirtyDays = "30D"
    }

    @Published var selectedPeriod: TimePeriod = .sevenDays
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
        stats = screenTimeManager.fetchStats()
    }
}
