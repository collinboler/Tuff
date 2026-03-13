import SwiftUI

struct LeagueHistoryRow: View {
    let entry: LeagueHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            RankCircle(rank: entry.placement)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.leagueName.uppercased())
                    .font(TuffFonts.historyName())
                    .foregroundColor(.white)
                    .tracking(0.03 * 15)

                Text(entry.dateRangeText)
                    .font(TuffFonts.caption(11))
                    .foregroundColor(TuffColors.textSecondary)
            }

            Spacer()

            Text(entry.earningsText)
                .font(TuffFonts.historyPayout())
                .foregroundColor(entry.earnings >= 0 ? TuffColors.accent : TuffColors.negative)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(TuffColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
