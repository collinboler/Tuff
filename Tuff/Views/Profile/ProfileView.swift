import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                topBar
                profileHero
                statsRow
                leagueHistory
            }
            .padding(.bottom, 16)
        }
        .background(Color.white)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text("PROFILE")
                .font(TuffFonts.pageTitle())
                .foregroundColor(.black)
                .tracking(0.06 * 26)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Profile Hero

    private var profileHero: some View {
        VStack(spacing: 6) {
            ProfileImageView(
                imageName: viewModel.user.imageName,
                size: 82,
                borderColor: TuffColors.accent,
                borderWidth: 3,
                uiImage: viewModel.profileImage
            )

            Text(viewModel.user.name.uppercased())
                .font(TuffFonts.profileName())
                .foregroundColor(.black)
                .tracking(0.05 * 26)
                .padding(.top, 4)

            Text("@\(viewModel.user.username)")
                .font(TuffFonts.caption(13))
                .foregroundColor(TuffColors.textSecondary)
        }
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 8) {
            profileStatBlock(value: "\(viewModel.user.totalLeagues)", label: "Leagues")
            profileStatBlock(value: "\(viewModel.user.leaguesWon)", label: "Won", isGreen: true)
            profileStatBlock(value: viewModel.totalEarningsFormatted, label: "Earned", isGreen: true)
        }
        .padding(.horizontal, 20)
    }

    private func profileStatBlock(value: String, label: String, isGreen: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(TuffFonts.profileStatValue())
                .foregroundColor(isGreen ? TuffColors.accent : .white)
            Text(label.uppercased())
                .font(TuffFonts.profileStatLabel())
                .foregroundColor(.gray)
                .tracking(0.08 * 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(TuffColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - League History

    private var leagueHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LEAGUE HISTORY")
                .font(TuffFonts.sectionHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.15 * 12)
                .padding(.horizontal, 22)
                .padding(.top, 20)

            VStack(spacing: 6) {
                ForEach(viewModel.leagueHistory) { entry in
                    LeagueHistoryRow(entry: entry)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

#Preview {
    ProfileView()
}
