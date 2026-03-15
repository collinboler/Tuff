import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                topBar
                wheelSection
                memberPanel
                divider
                leaguesSection
            }
            .padding(.bottom, 80)
        }
        .background(Color.white)
        .sheet(isPresented: $viewModel.showLeagueDetail) {
            if let league = viewModel.selectedLeague {
                LeagueDetailSheet(league: league)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $viewModel.showCreateLeague) {
            CreateLeagueView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Top Bar (padding 52 22 8 from HTML)

    private var topBar: some View {
        HStack {
            Text("TUFF")
                .font(TuffFonts.logo())
                .foregroundColor(TuffColors.accent)
                .tracking(0.09 * 30)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Wheel / Carousel

    private var wheelSection: some View {
        VStack(spacing: 0) {
            FriendCarouselView(
                users: viewModel.carouselUsers,
                currentUserId: viewModel.currentUser.id,
                onActiveIndexChanged: { idx in
                    viewModel.selectCarouselUser(at: idx)
                }
            )
            .frame(height: 190)

            // Gold pointer triangle
            Triangle()
                .fill(TuffColors.goldBright)
                .frame(width: 18, height: 14)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .padding(.top, -2)
        }
    }

    // MARK: - Member Panel

    private var memberPanel: some View {
        let user = viewModel.selectedCarouselUser
        let isYou = user.id == viewModel.currentUser.id
        let allUsers = viewModel.carouselUsers
        let rank = (allUsers.firstIndex(where: { $0.id == user.id }) ?? 0) + 1
        let leagueNames = viewModel.leagues
            .filter { $0.members.contains(where: { $0.user.id == user.id }) }
            .map { $0.name.uppercased() }

        return HStack(alignment: .center, spacing: 12) {
            ProfileImageView(
                imageName: user.imageName,
                size: 44,
                borderColor: TuffColors.accent,
                borderWidth: 2
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(isYou ? "\(user.name.uppercased()) (YOU)" : user.name.uppercased())
                    .font(TuffFonts.panelName())
                    .foregroundColor(.black)
                    .tracking(0.04 * 18)

                if !leagueNames.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(leagueNames, id: \.self) { name in
                            Text(name)
                                .font(TuffFonts.tag())
                                .foregroundColor(TuffColors.tagText)
                                .tracking(0.05 * 10)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(TuffColors.tagBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(user.formattedScreenTime)
                    .font(TuffFonts.panelTime())
                    .foregroundColor(TuffColors.accent)

                Text("RANK \(rank) OF \(allUsers.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(TuffColors.textSecondary)
                    .tracking(0.5)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .animation(.easeInOut(duration: 0.2), value: user.id)
    }

    private var divider: some View {
        Rectangle()
            .fill(TuffColors.divider)
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    // MARK: - Leagues Section

    private var leaguesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LEAGUES")
                .font(TuffFonts.sectionHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.15 * 12)
                .padding(.horizontal, 22)
                .padding(.top, 14)

            VStack(spacing: 8) {
                ForEach(viewModel.leagues) { league in
                    LeagueCardView(league: league)
                        .onTapGesture {
                            viewModel.selectLeague(league)
                        }
                }
            }
            .padding(.horizontal, 16)

            Button {
                viewModel.showCreateLeague = true
            } label: {
                Text("+ NEW LEAGUE")
                    .font(TuffFonts.newButton())
                    .foregroundColor(.black)
                    .tracking(0.09 * 17)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(TuffColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HomeView()
        .environmentObject(ScreenTimeManager.shared)
}
