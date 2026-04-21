import SwiftUI

struct LeagueCardView: View {
    let league: League

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(league.name.uppercased())
                        .font(TuffFonts.leagueCardName())
                        .foregroundColor(.white)
                        .tracking(0.05 * 16)

                    if league.hasEnded {
                        Text("ENDED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(TuffColors.goldBright)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .tracking(0.6)
                    }
                }

                Text(league.hasEnded ? league.dateRangeText : "\(league.dateRangeText) · \(league.timeRemainingText)")
                    .font(TuffFonts.caption(11))
                    .foregroundColor(league.hasEnded ? TuffColors.goldBright.opacity(0.85) : TuffColors.textSecondary)
            }

            Spacer()

            memberAvatars

            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "$%.2f", league.poolDollars))
                    .font(TuffFonts.leagueCardPot())
                    .foregroundColor(.white)

                Text(league.hasEnded ? "FINAL" : "\(league.pricePerHourCents)¢/hr")
                    .font(TuffFonts.caption(11))
                    .foregroundColor(TuffColors.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(TuffColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(league.hasEnded ? 0.88 : 1)
    }

    private var memberAvatars: some View {
        HStack(spacing: -7) {
            ForEach(Array(league.members.prefix(3).enumerated()), id: \.element.id) { index, member in
                ProfileImageView(
                    imageName: member.user.imageName,
                    size: 26
                )
                .zIndex(Double(3 - index))
            }
        }
        .padding(.trailing, 8)
    }
}
