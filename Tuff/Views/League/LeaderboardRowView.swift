import SwiftUI

struct LeaderboardRowView: View {
    let rank: Int
    let member: LeagueMember
    let isCurrentUser: Bool
    var joinedLate: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if member.isDQ {
                    Text("DQ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(width: 24, alignment: .center)
                } else {
                    Text("\(rank)")
                        .font(TuffFonts.lbRank())
                        .foregroundColor(rankColor)
                        .frame(width: 24, alignment: .center)
                }
            }

            ProfileImageView(
                imageName: member.user.imageName,
                size: 40,
                photoURL: member.user.photoURL
            )
            .opacity(member.isDQ ? 0.45 : 1)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(member.user.name.uppercased())
                        .font(TuffFonts.lbName())
                        .foregroundColor(member.isDQ ? TuffColors.textSecondary : .black)
                        .tracking(0.03 * 15)
                        .strikethrough(member.isDQ, color: TuffColors.textSecondary)

                    if isCurrentUser {
                        Text("(YOU)")
                            .font(TuffFonts.lbName())
                            .foregroundColor(member.isDQ ? TuffColors.textSecondary : .black)
                    }
                }

                HStack(spacing: 4) {
                    Text(member.formattedBoughtTime)
                        .font(TuffFonts.caption(11))
                        .foregroundColor(TuffColors.textSecondary)

                    if member.isDQ {
                        Text("· left league")
                            .font(TuffFonts.caption(11))
                            .foregroundColor(Color.red.opacity(0.7))
                    } else if joinedLate {
                        Text("· joined late")
                            .font(TuffFonts.caption(11))
                            .foregroundColor(Color.orange.opacity(0.8))
                    }
                }
            }

            Spacer()

            Text(member.formattedBoughtCost)
                .font(TuffFonts.lbTime())
                .foregroundColor(member.isDQ ? TuffColors.textSecondary : (member.boughtCents == 0 ? TuffColors.accent : .black))
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .opacity(member.isDQ ? 0.75 : 1)
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
