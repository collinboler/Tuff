import SwiftUI

struct LeaderboardRowView: View {
    let rank: Int
    let member: LeagueMember
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(TuffFonts.lbRank())
                .foregroundColor(rankColor)
                .frame(width: 24, alignment: .center)

            ProfileImageView(
                imageName: member.user.imageName,
                size: 40,
                borderColor: isCurrentUser ? TuffColors.accent : Color.gray.opacity(0.2),
                borderWidth: isCurrentUser ? 2.5 : 1.5
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(member.user.name.uppercased())
                        .font(TuffFonts.lbName())
                        .foregroundColor(.black)
                        .tracking(0.03 * 15)

                    if isCurrentUser {
                        Text("(YOU)")
                            .font(TuffFonts.lbName())
                            .foregroundColor(.black)
                    }
                }

                Text(member.lastUpdatedText)
                    .font(TuffFonts.caption(11))
                    .foregroundColor(TuffColors.textSecondary)
            }

            Spacer()

            Text(member.formattedScreenTime)
                .font(TuffFonts.lbTime())
                .foregroundColor(.black)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return TuffColors.gold
        case 2: return TuffColors.silver
        case 3: return TuffColors.bronze
        default: return TuffColors.rankOther
        }
    }
}
