import SwiftUI
import Charts

struct ScreenTimeChartView: View {
    let data: [DailyScreenTime]
    let period: StatsViewModel.TimePeriod

    var body: some View {
        Chart {
            ForEach(data) { day in
                AreaMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Hours", day.hours)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            TuffColors.chartLine.opacity(0.35),
                            TuffColors.chartLine.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Hours", day.hours)
                )
                .foregroundStyle(TuffColors.chartLine)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Hours", day.hours)
                )
                .foregroundStyle(TuffColors.chartLine)
                .symbolSize(20)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: period == .sevenDays ? .day : .weekOfYear)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(dayLabel(date))
                            .font(.system(size: 10))
                            .foregroundColor(TuffColors.chartLabel)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(TuffColors.chartGrid)
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text("\(Int(hours))h")
                            .font(.system(size: 9))
                            .foregroundColor(TuffColors.chartLabel)
                    }
                }
            }
        }
        .chartYScale(domain: 0...5)
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.clear)
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = period == .sevenDays ? "EEE" : "MMM d"
        return formatter.string(from: date)
    }
}
