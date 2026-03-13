import SwiftUI

struct LeagueCardView: View {
    let league: League

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(league.name.uppercased())
                    .font(TuffFonts.leagueCardName())
                    .foregroundColor(.white)
                    .tracking(0.05 * 16)

                Text(league.dateRangeText)
                    .font(TuffFonts.caption(11))
                    .foregroundColor(TuffColors.textSecondary)
            }

            Spacer()

            memberAvatars

            VStack(alignment: .trailing, spacing: 1) {
                Text("$\(Int(league.potAmount))")
                    .font(TuffFonts.leagueCardPot())
                    .foregroundColor(.white)

                Text("$\(Int(league.costPerPerson))/person")
                    .font(TuffFonts.caption(11))
                    .foregroundColor(TuffColors.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(TuffColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var memberAvatars: some View {
        HStack(spacing: -7) {
            ForEach(Array(league.members.prefix(3).enumerated()), id: \.element.id) { index, member in
                ProfileImageView(
                    imageName: member.user.imageName,
                    size: 26,
                    borderColor: index == 0 ? TuffColors.gold : TuffColors.surface,
                    borderWidth: 2
                )
                .zIndex(Double(3 - index))
            }
        }
        .padding(.trailing, 8)
    }
}
