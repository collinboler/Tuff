import SwiftUI

struct LeagueDetailSheet: View {
    let league: League
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    leaderboardSection
                    payoutSection
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.white)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(league.name.uppercased())
                    .font(TuffFonts.modalTitle())
                    .foregroundColor(.black)
                    .tracking(0.05 * 24)

                HStack(spacing: 10) {
                    Text(league.dateRangeText)
                        .font(TuffFonts.caption(12))
                        .foregroundColor(TuffColors.textSecondary)

                    Text("$\(Int(league.potAmount))")
                        .font(TuffFonts.modalPot())
                        .foregroundColor(TuffColors.accent)
                }
            }

            Spacer()

            Button {
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
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Leaderboard

    private var leaderboardSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(league.sortedMembers.enumerated()), id: \.element.id) { index, member in
                LeaderboardRowView(
                    rank: index + 1,
                    member: member,
                    isCurrentUser: member.user.isCurrentUser
                )

                if index < league.sortedMembers.count - 1 {
                    Divider()
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Payout

    private var payoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PAYOUT BREAKDOWN")
                .font(TuffFonts.payoutHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.14 * 11)

            ForEach(league.payoutBreakdown, id: \.place) { payout in
                HStack {
                    Text(payout.place)
                        .font(TuffFonts.body(13))
                        .foregroundColor(Color(hex: "555555"))

                    Spacer()

                    Text("$\(Int(payout.amount))")
                        .font(TuffFonts.payoutAmount())
                        .foregroundColor(TuffColors.accent)
                }
            }
        }
        .padding(20)
        .background(TuffColors.payoutBg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TuffColors.divider)
                .frame(height: 1)
        }
        .padding(.top, 8)
    }
}
