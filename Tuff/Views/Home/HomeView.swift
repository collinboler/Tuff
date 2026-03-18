import SwiftUI
import FamilyControls

struct LeagueView: View {
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                leaguesSection
            }
            .padding(.bottom, 16)
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
                .environmentObject(ScreenTimeManager.shared)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showJoinLeague) {
            JoinLeagueView(viewModel: viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text("LEAGUES")
                .font(TuffFonts.pageTitle())
                .foregroundColor(.black)
                .tracking(0.06 * 26)
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
        let userKey = user.uid.isEmpty ? user.id.uuidString : user.uid
        let leagueNames = viewModel.leagues
            .filter { $0.members.contains(where: {
                let k = $0.user.uid.isEmpty ? $0.user.id.uuidString : $0.user.uid
                return k == userKey
            })}
            .map { $0.name.uppercased() }

        return HStack(alignment: .center, spacing: 12) {
            ProfileImageView(
                imageName: user.imageName,
                size: 44
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

    // MARK: - Earnings Summary Row

    private var earningsRow: some View {
        HStack(spacing: 0) {
            earningsStat(value: "$\(Int(viewModel.currentUser.totalEarnings))", label: "TOTAL EARNED")
            Divider().frame(height: 36)
            earningsStat(value: "\(viewModel.currentUser.leaguesWon)", label: "LEAGUES WON")
            Divider().frame(height: 36)
            earningsStat(value: "\(viewModel.currentUser.totalLeagues)", label: "LEAGUES")
        }
        .padding(.vertical, 12)
    }

    private func earningsStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .black, design: .default).width(.condensed))
                .foregroundColor(TuffColors.accent)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
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
                .font(TuffFonts.logo())
                .foregroundColor(.black)
                .tracking(0.09 * 30)
                .padding(.horizontal, 22)
                .padding(.top, 16)

            VStack(spacing: 8) {
                ForEach(viewModel.leagues) { league in
                    LeagueCardView(league: league)
                        .onTapGesture { viewModel.selectLeague(league) }
                }
            }
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Button { viewModel.showCreateLeague = true } label: {
                    Text("+ NEW LEAGUE")
                        .font(TuffFonts.newButton())
                        .foregroundColor(.white)
                        .tracking(0.09 * 17)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(TuffColors.accent.opacity(0.5))
                                    .offset(y: 4)
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(LinearGradient(
                                        colors: [TuffColors.accent.opacity(0.95), TuffColors.accent],
                                        startPoint: .top, endPoint: .bottom
                                    ))
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(LinearGradient(
                                        colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                                        startPoint: .top, endPoint: .center
                                    ))
                            }
                        )
                        .shadow(color: TuffColors.accent.opacity(0.4), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(PressableButtonStyle())

                Button { viewModel.showJoinLeague = true } label: {
                    Text("JOIN")
                        .font(TuffFonts.newButton())
                        .foregroundColor(TuffColors.accent)
                        .tracking(0.09 * 17)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(TuffColors.accent.opacity(0.06))
                                    .offset(y: 3)
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(TuffColors.accent.opacity(0.10))
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .stroke(TuffColors.accent.opacity(0.45), lineWidth: 1.5))
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(LinearGradient(
                                        colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                                        startPoint: .top, endPoint: .center
                                    ))
                            }
                        )
                        .shadow(color: Color.black.opacity(0.14), radius: 6, x: 0, y: 4)
                }
                .buttonStyle(PressableButtonStyle())
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
