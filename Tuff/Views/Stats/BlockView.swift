import SwiftUI
import FirebaseAuth

struct BlockView: View {
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @EnvironmentObject var homeViewModel: HomeViewModel

    @State private var selectedMinutes: Int = 15
    @State private var isBuying = false
    @State private var isEndingBreak = false

    private let breakOptions: [(label: String, minutes: Int)] = [
        ("1 min", 1),
        ("5 min", 5),
        ("15 min", 15),
        ("30 min", 30),
        ("1 hr", 60),
        ("2 hr", 120),
        ("4 hr", 240)
    ]

    private var isOnBreak: Bool { screenTimeManager.blockTimerEndDate != nil }
    private var activeLeagues: [League] { homeViewModel.leagues.filter { $0.isActive } }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                if isOnBreak {
                    breakActiveView
                } else {
                    buyBreakView
                }

                Spacer()
            }
        }
    }

    // MARK: - Break Active

    private var breakActiveView: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 52))
                    .foregroundColor(TuffColors.accent)

                Text("BREAK ACTIVE")
                    .font(.system(size: 22, weight: .black, design: .default).width(.condensed))
                    .foregroundColor(.black)
                    .tracking(1)

                if let end = screenTimeManager.blockTimerEndDate {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .font(.system(size: 42, weight: .black, design: .monospaced).monospacedDigit())
                        .foregroundColor(TuffColors.accent)
                }

                Text("Apps unlocked until break ends")
                    .font(.system(size: 14))
                    .foregroundColor(TuffColors.textSecondary)

                if !screenTimeManager.liveActivitiesEnabled {
                    Label("Enable Live Activities in Settings › Tuff to see the timer in your Dynamic Island", systemImage: "bell.slash")
                        .font(.system(size: 12))
                        .foregroundColor(TuffColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            if !activeLeagues.isEmpty {
                VStack(spacing: 6) {
                    Text("LEDGER UPDATE")
                        .font(TuffFonts.sectionHeader())
                        .foregroundColor(TuffColors.textSecondary)
                        .tracking(0.15 * 12)
                    ForEach(activeLeagues) { league in
                        HStack {
                            Text(league.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.black)
                            Spacer()
                            Text("–\(breakCostText(minutes: selectedMinutes, league: league))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 12)
                .background(Color(hex: "F8F8F8"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 32)
            }

            VStack(spacing: 8) {
                if let savings = refundSummaryText {
                    Text(savings)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TuffColors.accent)
                }

                Button {
                    guard !isEndingBreak else { return }
                    isEndingBreak = true
                    guard let uid = Auth.auth().currentUser?.uid else {
                        screenTimeManager.cancelBlockTimer()
                        isEndingBreak = false
                        return
                    }
                    let leagues = activeLeagues
                    let refundMins = refundMinutesAvailable
                    if refundMins > 0 {
                        homeViewModel.applyOptimisticRefund(uid: uid, refundMinutes: refundMins)
                    }
                    Task {
                        await screenTimeManager.cancelBreakEarly(uid: uid, leagues: leagues)
                        await MainActor.run { isEndingBreak = false }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isEndingBreak {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("End Break Early")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.red.opacity(0.5))
                                .offset(y: 4)
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(
                                    colors: [Color.red.opacity(0.9), Color.red.opacity(0.8)],
                                    startPoint: .top, endPoint: .bottom
                                ))
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(
                                    colors: [Color.white.opacity(0.2), Color.white.opacity(0)],
                                    startPoint: .top, endPoint: .center
                                ))
                        }
                    )
                    .shadow(color: Color.red.opacity(0.4), radius: 10, x: 0, y: 5)
                }
                .disabled(isEndingBreak)
                .padding(.horizontal, 40)
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    // MARK: - Buy Break

    private var buyBreakView: some View {
        VStack(spacing: 28) {
            lockStatusHeader

            durationPicker

            if !activeLeagues.isEmpty {
                costBreakdown
            }

            buyButton
        }
    }

    private var lockStatusHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundColor(.black)

            Text("APPS LOCKED")
                .font(.system(size: 22, weight: .black, design: .default).width(.condensed))
                .foregroundColor(.black)
                .tracking(1)

            Text("All app categories blocked by your league")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BREAK DURATION")
                .font(TuffFonts.sectionHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.15 * 12)
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(breakOptions, id: \.minutes) { option in
                        let isSelected = selectedMinutes == option.minutes
                        Button {
                            selectedMinutes = option.minutes
                        } label: {
                            VStack(spacing: 2) {
                                Text(option.label)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(isSelected ? .white : .black)
                                if !activeLeagues.isEmpty, let firstLeague = activeLeagues.first {
                                    Text(breakCostText(minutes: option.minutes, league: firstLeague))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(isSelected ? Color.white.opacity(0.8) : TuffColors.textSecondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isSelected ? TuffColors.accent.opacity(0.5) : Color(hex: "E8E8E8"))
                                        .offset(y: 3)
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isSelected
                                              ? LinearGradient(colors: [TuffColors.accent.opacity(0.95), TuffColors.accent],
                                                               startPoint: .top, endPoint: .bottom)
                                              : LinearGradient(colors: [Color.white, Color(hex: "F0F0F0")],
                                                               startPoint: .top, endPoint: .bottom))
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(LinearGradient(
                                            colors: [Color.white.opacity(0.2), Color.white.opacity(0)],
                                            startPoint: .top, endPoint: .center
                                        ))
                                }
                            )
                            .shadow(color: isSelected ? TuffColors.accent.opacity(0.4) : Color.black.opacity(0.12),
                                    radius: isSelected ? 8 : 4, x: 0, y: isSelected ? 4 : 2)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }
        }
    }

    private var costBreakdown: some View {
        VStack(spacing: 0) {
            HStack {
                Text("COST PER LEAGUE")
                    .font(TuffFonts.sectionHeader())
                    .foregroundColor(TuffColors.textSecondary)
                    .tracking(0.15 * 12)
                Spacer()
                Text("\(selectedMinutes) min break")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TuffColors.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(activeLeagues.enumerated()), id: \.element.id) { i, league in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(league.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                            Text("\(league.pricePerHourCents)¢/hr rate")
                                .font(.system(size: 11))
                                .foregroundColor(TuffColors.textSecondary)
                        }
                        Spacer()
                        Text("–\(breakCostText(minutes: selectedMinutes, league: league))")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color.red.opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if i < activeLeagues.count - 1 {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .background(Color(hex: "F8F8F8"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "EEEEEE"), lineWidth: 1))
            .padding(.horizontal, 24)
        }
    }

    private var buyButton: some View {
        Button {
            guard !isBuying else { return }
            isBuying = true
            guard let uid = Auth.auth().currentUser?.uid else { isBuying = false; return }
            let leagues = activeLeagues
            let minutes = selectedMinutes
            // Optimistic update — leaderboard reflects the charge immediately
            homeViewModel.applyOptimisticBreakCharge(uid: uid, minutes: minutes)
            Task {
                await screenTimeManager.buyBreak(minutes: minutes, uid: uid, leagues: leagues)
                await MainActor.run { isBuying = false }
            }
        } label: {
            HStack(spacing: 10) {
                if isBuying {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Buy \(selectedMinutes) min Break")
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(TuffColors.accent.opacity(0.55))
                        .offset(y: 4)
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(
                            colors: [TuffColors.accent.opacity(0.95), TuffColors.accent],
                            startPoint: .top, endPoint: .bottom
                        ))
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                            startPoint: .top, endPoint: .center
                        ))
                }
            )
            .shadow(color: TuffColors.accent.opacity(0.45), radius: 12, x: 0, y: 6)
        }
        .disabled(isBuying)
        .padding(.horizontal, 32)
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Helpers

    private func breakCostText(minutes: Int, league: League) -> String {
        let cents = max(1, Int(round(Double(minutes) / 60.0 * Double(league.pricePerHourCents))))
        return String(format: "$%.2f", Double(cents) / 100.0)
    }

    /// Minutes that would be refunded if the break is ended right now.
    /// = originalMinutes - floor(secondsUsed / 60)
    /// Matches the rule: only full minutes used are charged; sub-minute = 0.
    private var refundMinutesAvailable: Int {
        guard let startDate = screenTimeManager.breakStartDate,
              let endDate   = screenTimeManager.blockTimerEndDate else { return 0 }
        let originalMinutes = Int((endDate.timeIntervalSince(startDate) / 60).rounded())
        let secondsUsed     = max(0, Date().timeIntervalSince(startDate))
        let minutesKept     = Int(secondsUsed / 60)          // floor
        return max(0, originalMinutes - minutesKept)
    }

    /// Total cents that would be refunded across all active leagues right now.
    private var totalRefundCents: Int {
        let mins = refundMinutesAvailable
        guard mins > 0 else { return 0 }
        return activeLeagues.reduce(0) { sum, league in
            sum + max(0, Int(round(Double(mins) / 60.0 * Double(league.pricePerHourCents))))
        }
    }

    private var refundSummaryText: String? {
        let mins = refundMinutesAvailable
        guard mins > 0, !activeLeagues.isEmpty else { return nil }
        let dollars = String(format: "$%.2f", Double(totalRefundCents) / 100.0)
        return "End \(mins)m early → save \(dollars)"
    }
}

// MARK: - Press-down animation

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
