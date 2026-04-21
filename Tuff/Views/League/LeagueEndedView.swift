import SwiftUI
import FirebaseAuth

/// Final-results screen shown when a league's end date has passed.
///
/// Winner-takes-all:
///   * Winner = lowest-spent non-DQ member (ties broken by earliest-joined).
///   * Every other member owes their `boughtCents` to the winner.
///
/// The current user sees a personalized "You won" / "You owe" summary plus the
/// full breakdown of who pays whom.
struct LeagueEndedView: View {
    let league: League
    var onDismiss: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    private var currentUID: String { Auth.auth().currentUser?.uid ?? "" }
    private var currentMember: LeagueMember? {
        league.members.first { $0.user.uid == currentUID }
    }
    private var userWon: Bool { league.winner?.user.uid == currentUID }
    private var netCents: Int { league.netOutcomeCents(forUid: currentUID) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    headerSection
                    winnerSpotlight
                    personalOutcomeCard
                    finalStandingsSection
                    if !league.finalPayments.isEmpty {
                        paymentsSection
                    }
                }
                .padding(20)
            }

            doneButton
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, 6)
        }
        .background(Color.white)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LEAGUE ENDED")
                    .font(TuffFonts.sectionHeader())
                    .foregroundColor(TuffColors.textSecondary)
                    .tracking(0.18 * 12)
                Spacer()
                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("✕")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(TuffColors.modalCloseText)
                        .frame(width: 30, height: 30)
                        .background(TuffColors.modalCloseBg)
                        .clipShape(Circle())
                }
            }

            Text(league.name.uppercased())
                .font(TuffFonts.modalTitle())
                .foregroundColor(.black)
                .tracking(0.05 * 24)

            HStack(spacing: 10) {
                Text(league.dateRangeText)
                    .font(TuffFonts.caption(12))
                    .foregroundColor(TuffColors.textSecondary)

                Text(String(format: "$%.2f pool", league.poolDollars))
                    .font(TuffFonts.modalPot())
                    .foregroundColor(TuffColors.accent)
            }
        }
    }

    // MARK: - Winner Spotlight

    @ViewBuilder
    private var winnerSpotlight: some View {
        if let winner = league.winner {
            HStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    ProfileImageView(
                        imageName: winner.user.imageName,
                        size: 62,
                        photoURL: winner.user.photoURL
                    )
                    .overlay(
                        Circle().stroke(TuffColors.gold, lineWidth: 3)
                    )
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14))
                        .foregroundColor(TuffColors.goldBright)
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.85)))
                        .offset(x: 4, y: -4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("WINNER")
                        .font(TuffFonts.sectionHeader())
                        .foregroundColor(TuffColors.gold)
                        .tracking(0.2 * 12)

                    Text(winner.user.name.uppercased())
                        .font(TuffFonts.panelName())
                        .foregroundColor(.black)
                        .tracking(0.04 * 18)
                        .lineLimit(1)

                    Text("Spent \(winner.formattedBoughtCost) · Takes \(String(format: "$%.2f", league.poolDollars))")
                        .font(TuffFonts.caption(12))
                        .foregroundColor(TuffColors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(TuffColors.payoutBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(TuffColors.gold.opacity(0.35), lineWidth: 1)
            )
        } else {
            Text("No eligible winner — every member was disqualified.")
                .font(TuffFonts.body(13))
                .foregroundColor(TuffColors.textSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TuffColors.payoutBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Personal Outcome

    @ViewBuilder
    private var personalOutcomeCard: some View {
        let absDollars = String(format: "$%.2f", Double(abs(netCents)) / 100.0)

        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR RESULT")
                .font(TuffFonts.sectionHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.2 * 12)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(outcomeHeadline)
                    .font(TuffFonts.panelName())
                    .foregroundColor(.black)
                    .tracking(0.04 * 18)
                Spacer()
                Text(signedAmount(absDollars))
                    .font(TuffFonts.historyPayout())
                    .foregroundColor(outcomeTint)
                    .monospacedDigit()
            }

            Text(outcomeSubtitle)
                .font(TuffFonts.caption(12))
                .foregroundColor(TuffColors.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(outcomeTint.opacity(0.08))
        )
    }

    private var outcomeHeadline: String {
        if currentMember == nil { return "NOT A MEMBER" }
        if userWon { return "YOU WON!" }
        if netCents == 0 { return "YOU BROKE EVEN" }
        if currentMember?.isDQ == true { return "YOU WERE DQ'D" }
        return "YOU OWE"
    }

    private var outcomeSubtitle: String {
        guard let me = currentMember else {
            return "You weren't a member of this league."
        }
        if userWon {
            return "Lowest spent takes the pool. Collect from each member below."
        }
        if me.isDQ {
            return "You left mid-season so you're ineligible to win, but your spend still contributes to the pool."
        }
        if netCents == 0 {
            return "You didn't spend anything on breaks — nothing to pay."
        }
        if let winnerName = league.winner?.user.name, !winnerName.isEmpty {
            return "Pay \(winnerName) the amount above to settle your spend."
        }
        return "Pay the amount above to settle your spend."
    }

    private func signedAmount(_ text: String) -> String {
        if userWon { return "+\(text)" }
        if netCents == 0 { return text }
        return "-\(text)"
    }

    private var outcomeTint: Color {
        if userWon { return TuffColors.accent }
        if netCents == 0 { return TuffColors.textSecondary }
        return TuffColors.negative
    }

    // MARK: - Final Standings

    private var finalStandingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FINAL STANDINGS")
                .font(TuffFonts.sectionHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.2 * 12)

            VStack(spacing: 0) {
                ForEach(Array(league.sortedMembers.enumerated()), id: \.element.id) { index, member in
                    LeaderboardRowView(
                        rank: index + 1,
                        member: member,
                        isCurrentUser: member.user.isCurrentUser,
                        joinedLate: league.isLateJoiner(member)
                    )

                    if index < league.sortedMembers.count - 1 {
                        Divider()
                            .padding(.horizontal, 20)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(TuffColors.payoutBg)
            )
        }
    }

    // MARK: - Payments

    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHO PAYS WHOM")
                .font(TuffFonts.sectionHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.2 * 12)

            VStack(spacing: 6) {
                ForEach(league.finalPayments) { payment in
                    paymentRow(payment)
                }
            }

            Text("Winner collects each loser's spend. Settle amounts however your league usually pays.")
                .font(TuffFonts.caption(11))
                .foregroundColor(TuffColors.textSecondary)
        }
    }

    private func paymentRow(_ payment: LeaguePayment) -> some View {
        let isYouPaying = payment.from.user.uid == currentUID
        let isYouReceiving = payment.to.user.uid == currentUID

        return HStack(spacing: 12) {
            ProfileImageView(
                imageName: payment.from.user.imageName,
                size: 34,
                photoURL: payment.from.user.photoURL
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(isYouPaying
                     ? "YOU → \(payment.to.user.name.uppercased())"
                     : "\(payment.from.user.name.uppercased()) → \(isYouReceiving ? "YOU" : payment.to.user.name.uppercased())")
                    .font(TuffFonts.lbName())
                    .foregroundColor(.black)
                    .tracking(0.03 * 15)
                    .lineLimit(1)

                Text(payment.from.isDQ ? "DQ'd — still contributes to pool" : "Spent \(payment.from.formattedBoughtCost)")
                    .font(TuffFonts.caption(11))
                    .foregroundColor(TuffColors.textSecondary)
            }

            Spacer()

            Text(payment.amountText)
                .font(TuffFonts.historyPayout())
                .foregroundColor(
                    isYouReceiving ? TuffColors.accent :
                    (isYouPaying ? TuffColors.negative : .black)
                )
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isYouPaying ? TuffColors.negative.opacity(0.06) :
                    isYouReceiving ? TuffColors.accent.opacity(0.08) :
                    TuffColors.payoutBg
                )
        )
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button {
            onDismiss()
            dismiss()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(TuffColors.accent)
                    .frame(height: 52)
                Text("DONE")
                    .font(TuffFonts.newButton())
                    .foregroundColor(.white)
                    .tracking(0.09 * 17)
            }
        }
        .buttonStyle(PressableButtonStyle())
    }
}
