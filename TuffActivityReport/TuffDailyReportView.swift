import SwiftUI
import Charts
import FamilyControls
import ManagedSettings

struct TuffDailyReportView: View {
    let data: ReportData

    @State private var showFullMonth = false
    @State private var selectedDate: Date? = Calendar.current.startOfDay(for: Date())
    @State private var selectedSlice: Int? = nil

    private let surface = Color(red: 26/255, green: 26/255, blue: 26/255)
    private let accent = Color(red: 0/255, green: 206/255, blue: 109/255)
    private let labelGray = Color(red: 136/255, green: 136/255, blue: 136/255)
    private let chartLine = Color(red: 0/255, green: 206/255, blue: 109/255)
    private let chartGrid = Color.white.opacity(0.08)

    private let fallbackColors: [Color] = [
        Color(red: 0/255, green: 206/255, blue: 109/255),
        Color(red: 88/255, green: 166/255, blue: 255/255),
        Color(red: 255/255, green: 149/255, blue: 0/255),
        Color(red: 255/255, green: 59/255, blue: 48/255),
        Color(red: 175/255, green: 82/255, blue: 222/255),
        Color(red: 255/255, green: 204/255, blue: 0/255),
        Color(red: 90/255, green: 200/255, blue: 250/255),
        Color(red: 255/255, green: 105/255, blue: 180/255),
        Color(red: 120/255, green: 120/255, blue: 128/255),
    ]

    private let brandColors: [String: Color] = [
        // Social
        "com.zhiliaoapp.musically":        Color(red: 254/255, green: 44/255, blue: 85/255),   // TikTok pink-red
        "com.burbn.instagram":             Color(red: 225/255, green: 48/255, blue: 108/255),   // Instagram pink
        "com.facebook.Facebook":           Color(red: 24/255, green: 119/255, blue: 242/255),   // Facebook blue
        "com.facebook.Messenger":          Color(red: 6/255, green: 149/255, blue: 255/255),    // Messenger blue
        "com.toyopagroup.picaboo":         Color(red: 255/255, green: 252/255, blue: 0/255),    // Snapchat yellow
        "com.atebits.Tweetie2":            Color(red: 29/255, green: 161/255, blue: 242/255),   // X/Twitter blue
        "com.reddit.Reddit":               Color(red: 255/255, green: 69/255, blue: 0/255),     // Reddit orange
        "com.linkedin.LinkedIn":           Color(red: 10/255, green: 102/255, blue: 194/255),   // LinkedIn blue
        "com.pinterest":                   Color(red: 230/255, green: 0/255, blue: 35/255),     // Pinterest red
        "ph.telegra.Telegraph":            Color(red: 0/255, green: 136/255, blue: 204/255),    // Telegram blue
        "net.whatsapp.WhatsApp":           Color(red: 37/255, green: 211/255, blue: 102/255),   // WhatsApp green
        "com.hammerandchisel.discord":     Color(red: 88/255, green: 101/255, blue: 242/255),   // Discord blurple
        "com.burbn.threads":               Color.white,                                          // Threads
        "AlexisBarreyworthy.BeReal":       Color.white,                                          // BeReal
        // Video & Streaming
        "com.google.ios.youtube":          Color(red: 255/255, green: 0/255, blue: 0/255),      // YouTube red
        "com.netflix.Netflix":             Color(red: 229/255, green: 9/255, blue: 20/255),     // Netflix red
        "tv.twitch":                       Color(red: 145/255, green: 70/255, blue: 255/255),   // Twitch purple
        "com.spotify.client":              Color(red: 29/255, green: 185/255, blue: 84/255),    // Spotify green
        "com.apple.tv":                    Color(red: 45/255, green: 45/255, blue: 45/255),     // Apple TV+ dark
        // Apple apps
        "com.apple.MobileSMS":             Color(red: 52/255, green: 199/255, blue: 89/255),    // Messages green
        "com.apple.mobilesafari":          Color(red: 0/255, green: 122/255, blue: 255/255),    // Safari blue
        "com.apple.mobilemail":            Color(red: 0/255, green: 122/255, blue: 255/255),    // Mail blue
        "com.apple.mobilephone":           Color(red: 52/255, green: 199/255, blue: 89/255),    // Phone green
        "com.apple.facetime":              Color(red: 50/255, green: 215/255, blue: 75/255),    // FaceTime green
        "com.apple.Music":                 Color(red: 252/255, green: 60/255, blue: 68/255),    // Apple Music red
        "com.apple.Photos":               Color(red: 255/255, green: 159/255, blue: 10/255),    // Photos gradient (orange)
        "com.apple.Maps":                  Color(red: 0/255, green: 122/255, blue: 255/255),    // Maps blue
        "com.apple.mobilecal":             Color(red: 255/255, green: 59/255, blue: 48/255),    // Calendar red
        "com.apple.mobilenotes":           Color(red: 255/255, green: 214/255, blue: 10/255),   // Notes yellow
        "com.apple.AppStore":              Color(red: 0/255, green: 122/255, blue: 255/255),    // App Store blue
        "com.apple.Preferences":           Color(red: 142/255, green: 142/255, blue: 147/255),  // Settings gray
        "com.apple.camera":                Color(red: 142/255, green: 142/255, blue: 147/255),  // Camera gray
        "com.apple.mobiletimer":           Color.white,                                          // Clock
        "com.apple.weather":               Color(red: 0/255, green: 160/255, blue: 230/255),    // Weather blue
        "com.apple.news":                  Color(red: 252/255, green: 60/255, blue: 68/255),    // News red
        "com.apple.Health":                Color(red: 255/255, green: 59/255, blue: 48/255),    // Health red
        "com.apple.Fitness":               Color(red: 0/255, green: 206/255, blue: 109/255),    // Fitness green
        "com.apple.podcasts":              Color(red: 135/255, green: 60/255, blue: 195/255),   // Podcasts purple
        // Google
        "com.google.chrome.ios":           Color(red: 66/255, green: 133/255, blue: 244/255),   // Chrome blue
        "com.google.Gmail":                Color(red: 234/255, green: 67/255, blue: 53/255),    // Gmail red
        "com.google.Maps":                 Color(red: 52/255, green: 168/255, blue: 83/255),    // Google Maps green
        // Shopping & Services
        "com.amazon.Amazon":               Color(red: 255/255, green: 153/255, blue: 0/255),    // Amazon orange
        "com.ubercab.UberClient":          Color.white,                                          // Uber
        "com.ubereats.UberEats":           Color(red: 6/255, green: 164/255, blue: 81/255),    // Uber Eats green
        "com.doordash.DoorDashConsumer":   Color(red: 255/255, green: 48/255, blue: 8/255),    // DoorDash red
        // Finance
        "com.venmo.Venmo":                 Color(red: 0/255, green: 141/255, blue: 210/255),    // Venmo blue
        "com.squareup.cash":               Color(red: 0/255, green: 214/255, blue: 50/255),    // Cash App green
        // Gaming
        "com.roblox.robloxmobile":         Color(red: 226/255, green: 35/255, blue: 26/255),   // Roblox red
        "com.mojang.minecraftpe":          Color(red: 98/255, green: 180/255, blue: 74/255),   // Minecraft green
        // Productivity
        "com.tinyspeck.chatlyio":          Color(red: 74/255, green: 21/255, blue: 75/255),    // Slack purple
        "com.microsoft.teams":             Color(red: 75/255, green: 73/255, blue: 172/255),    // Teams purple
        "com.instructure.icanvas":         Color(red: 212/255, green: 45/255, blue: 31/255),   // Canvas red
        "com.zoom.VideoClient":            Color(red: 45/255, green: 140/255, blue: 255/255),   // Zoom blue
    ]

    private func colorForApp(_ app: ReportData.AppEntry, at index: Int) -> Color {
        if let bid = app.bundleID, let c = brandColors[bid] { return c }
        return fallbackColors[index % fallbackColors.count]
    }

    // MARK: - Computed

    private var todayStart: Date { Calendar.current.startOfDay(for: Date()) }

    private var chartData: [ReportData.DayData] {
        let calendar = Calendar.current
        let daysBack = showFullMonth ? 29 : 6
        let cutoff = calendar.date(byAdding: .day, value: -daysBack, to: todayStart)!
        return (0...daysBack).compactMap { offset -> ReportData.DayData? in
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: cutoff)
                    .map({ calendar.startOfDay(for: $0) }) else { return nil }
            // Try exact match first, then fuzzy same-day match
            return data.days.first(where: { $0.date == dayStart })
                ?? data.days.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) })
                ?? ReportData.DayData(date: dayStart, totalSeconds: 0, apps: [])
        }
    }

    private var activeDay: ReportData.DayData? {
        let target = selectedDate ?? todayStart
        return chartData.first { Calendar.current.isDate($0.date, inSameDayAs: target) }
    }

    private var activeDayLabel: String {
        guard let day = activeDay else { return "TODAY" }
        if Calendar.current.isDateInToday(day.date) { return "TODAY" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: day.date).uppercased()
    }

    private var chartYMax: Double {
        max(1, (chartData.map(\.hours).max() ?? 1) * 1.2)
    }

    private var chartXDomain: ClosedRange<Date>? {
        guard let first = chartData.first?.date,
              let last = chartData.last?.date else { return nil }
        return first...last.addingTimeInterval(43200)
    }

    private var xAxisDates: [Date] {
        if showFullMonth {
            return chartData.enumerated().compactMap { index, point in
                let isMajorTick = index % 5 == 0 || index == chartData.count - 1
                return isMajorTick ? point.date : nil
            }
        }
        return chartData.map(\.date)
    }

    // private var averageSeconds: TimeInterval? {
    //     let calendar = Calendar.current
    //     let daysBack = showFullMonth ? 29 : 6
    //     let cutoff = calendar.date(byAdding: .day, value: -daysBack, to: todayStart)!
    //     let filtered = chartData.filter {
    //         $0.date >= cutoff && $0.date < todayStart && $0.hours > 0
    //     }
    //     guard !filtered.isEmpty else { return nil }
    //     return filtered.map(\.totalSeconds).reduce(0, +) / Double(filtered.count)
    // }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                periodToggle
                interactiveChart
                breakdownSection
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header + Period Toggle

    private var periodToggle: some View {
        HStack {
            Text("YOUR STATS")
                .font(.system(size: 26, weight: .black).width(.condensed))
                .foregroundColor(.black)
                .tracking(0.06 * 26)
            Spacer()
            HStack(spacing: 0) {
                toggleButton("7D", active: !showFullMonth) {
                    showFullMonth = false
                    selectedDate = todayStart
                    selectedSlice = nil
                }
                toggleButton("30D", active: showFullMonth) {
                    showFullMonth = true
                    selectedDate = todayStart
                    selectedSlice = nil
                }
            }
            .padding(2)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.gray.opacity(0.25), lineWidth: 1))
        }
    }

    private func toggleButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .heavy).width(.condensed))
                .foregroundColor(active ? .white : .gray)
                .tracking(0.7)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(active ? accent : Color.clear)
                .clipShape(Capsule())
        }
    }

    // MARK: - Interactive Chart

    private var interactiveChart: some View {
        Group {
            if chartData.isEmpty {
                Text("No data yet")
                    .foregroundColor(labelGray)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        let day = selectedDate.flatMap({ sel in
                            chartData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: sel) })
                        })
                        let label = day.map { shortDayLabel($0.date) } ?? "Today"
                        let time = day.map { fmt($0.totalSeconds) } ?? data.todayFormatted

                        Text(label)
                            .font(.system(size: 22, weight: .bold).width(.condensed))
                            .foregroundColor(accent)
                        Text(time)
                            .font(.system(size: 22, weight: .black).width(.condensed))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    Chart {
                        RuleMark(x: .value("Selected", selectedDate ?? todayStart, unit: .day))
                            .foregroundStyle(.white)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))

                        ForEach(chartData) { point in
                            let isSelected = Calendar.current.isDate(
                                point.date, inSameDayAs: selectedDate ?? todayStart)

                            AreaMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Hours", point.hours)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [chartLine.opacity(0.35), chartLine.opacity(0.0)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Hours", point.hours)
                            )
                            .foregroundStyle(chartLine)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Hours", point.hours)
                            )
                            .foregroundStyle(Color.clear)
                            .symbolSize(1)
                            .annotation(position: .overlay, alignment: .center, spacing: 0) {
                                if isSelected {
                                    ZStack {
                                        Circle()
                                            .fill(chartLine.opacity(0.25))
                                            .frame(width: 20, height: 20)
                                        Circle()
                                            .fill(chartLine)
                                            .frame(width: 10, height: 10)
                                    }
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(surface)
                                            .frame(width: 8, height: 8)
                                        Circle()
                                            .strokeBorder(chartLine, lineWidth: 1.5)
                                            .frame(width: 8, height: 8)
                                    }
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: xAxisDates) { value in
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(xAxisLabel(date))
                                        .font(.system(size: 10))
                                        .foregroundColor(labelGray)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(chartGrid)
                            AxisValueLabel {
                                if let hours = value.as(Double.self) {
                                    Text("\(Int(hours))h")
                                        .font(.system(size: 9))
                                        .foregroundColor(labelGray)
                                }
                            }
                        }
                    }
                    .chartYScale(domain: 0...chartYMax)
                    .chartXScale(domain: chartXDomain ?? todayStart...todayStart)
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            let plotFrame = geo[proxy.plotAreaFrame]
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                                            let x = value.location.x - plotFrame.origin.x
                                            guard let rawDate: Date = proxy.value(atX: x) else { return }
                                            snapToNearest(rawDate)
                                        }
                                )
                        }
                    }
                    .frame(height: 140)
                }
            }
        }
        .padding(16)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Breakdown Section

    private var breakdownSection: some View {
        VStack(spacing: 12) {
            if let day = activeDay, !day.apps.isEmpty {
                VStack(spacing: 18) {
                    donutChart(apps: day.apps, total: day.totalSeconds)
                        .frame(width: 130, height: 130)

                    appList(apps: day.apps)
                }
                .padding(.top, 4)
                .id(activeDay?.date ?? Date.distantPast)
            } else {
                Text("No app data")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(labelGray)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .padding(16)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Donut Chart

    private func donutChart(apps: [ReportData.AppEntry], total: TimeInterval) -> some View {
        let fractions = apps.map { $0.seconds / max(total, 1) }

        return ZStack {
            ForEach(apps.indices, id: \.self) { i in
                let start = fractions.prefix(i).reduce(0, +)
                let end = start + fractions[i]
                Circle()
                    .trim(from: CGFloat(start), to: CGFloat(end) - 0.005)
                    .stroke(
                        colorForApp(apps[i], at: i),
                        style: StrokeStyle(
                            lineWidth: selectedSlice == i ? 22 : 18,
                            lineCap: .butt
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .onTapGesture { selectedSlice = selectedSlice == i ? nil : i }
            }

            VStack(spacing: 1) {
                Text(fmt(total))
                    .font(.system(size: 16, weight: .black).width(.condensed))
                    .foregroundColor(.white)
                Text("TOTAL")
                    .font(.system(size: 8, weight: .bold).width(.condensed))
                    .foregroundColor(labelGray)
            }
        }
        .padding(14)
    }

    // MARK: - App List

    private func appList(apps: [ReportData.AppEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                let appColor = colorForApp(app, at: index)
                HStack(spacing: 10) {
                    Circle()
                        .fill(appColor)
                        .frame(width: 10, height: 10)

                    Label(app.application.token!)
                        .labelStyle(.iconOnly)
                        .scaleEffect(0.8)
                        .frame(width: 28, height: 28)

                    Label(app.application.token!)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    Text(fmt(app.seconds))
                        .font(.system(size: 14, weight: .heavy).width(.condensed))
                        .foregroundColor(
                            selectedSlice == index ? appColor : labelGray
                        )
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedSlice = selectedSlice == index ? nil : index }
                .opacity(selectedSlice == nil || selectedSlice == index ? 1.0 : 0.4)
            }
        }
    }

    // MARK: - Helpers

    private func snapToNearest(_ rawDate: Date) {
        let target = Calendar.current.startOfDay(for: rawDate)
        if let nearest = chartData.min(by: {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        }) {
            selectedDate = nearest.date
            selectedSlice = nil
        }
    }

    private func fmt(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h == 0 && m == 0 { return "0m" }
        if h == 0 { return "\(m)m" }
        return "\(h)h \(String(format: "%02d", m))m"
    }

    private func xAxisLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = showFullMonth ? "MMM d" : "EEE"
        return f.string(from: date)
    }

    private func shortDayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }
}
