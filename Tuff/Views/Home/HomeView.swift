import SwiftUI

struct LeagueView: View {
    @EnvironmentObject var viewModel: HomeViewModel

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    private var wheelEntries: [FriendCarouselEntry] {
        viewModel.carouselUsers.map {
            FriendCarouselEntry(
                id: $0.id,
                name: $0.name,
                imageName: $0.imageName,
                photoURL: $0.photoURL,
                dailySpentCents: viewModel.dailySpentCents(for: $0),
                isCurrentUser: $0.isCurrentUser
            )
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                topBar
                wheelSection
                memberPanel
                divider
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
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showJoinLeague) {
            JoinLeagueView(viewModel: viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Image("title")
                .resizable()
                .scaledToFit()
                .frame(height: 54)
            Spacer()
        }
        .padding(.top, 52)
        .padding(.bottom, 10)
        .zIndex(0)
    }

    private var wheelSection: some View {
        ZStack(alignment: .bottom) {
            FriendCarouselView(
                entries: wheelEntries,
                currentEntryId: viewModel.currentUser.id,
                onActiveIndexChanged: { idx in
                    viewModel.selectCarouselUser(at: idx)
                }
            )
            .frame(height: 190)

            Image("pointer")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 18)
                .offset(y: -32)
                .allowsHitTesting(false)
        }
        .frame(height: 190)
        .zIndex(1)
    }

    private var memberPanel: some View {
        let user = viewModel.selectedCarouselUser
        let allUsers = viewModel.carouselUsers
        let userKey = user.uid.isEmpty ? user.id.uuidString : user.uid
        let userRank = (allUsers.firstIndex(where: {
            let key = $0.uid.isEmpty ? $0.id.uuidString : $0.uid
            return key == userKey
        }) ?? 0) + 1
        let leagueNames = Array(Set(viewModel.leagues
            .filter { league in
                league.members.contains(where: { member in
                    let key = member.user.uid.isEmpty ? member.user.id.uuidString : member.user.uid
                    return key == userKey
                })
            }
            .map { $0.name.uppercased() }))
            .sorted()

        return HStack(alignment: .center, spacing: 12) {
            ProfileImageView(
                imageName: user.imageName,
                size: 44,
                photoURL: user.photoURL
            )
            .overlay(
                Circle()
                    .stroke(TuffColors.accent, lineWidth: 2)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(user.isCurrentUser ? "\(user.name.uppercased()) (YOU)" : user.name.uppercased())
                    .font(TuffFonts.panelName())
                    .foregroundColor(.black)
                    .tracking(0.04 * 18)
                    .lineLimit(1)

                if !leagueNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(leagueNames, id: \.self) { name in
                                Text(name)
                                    .font(TuffFonts.tag())
                                    .foregroundColor(TuffColors.tagText)
                                    .tracking(0.05 * 10)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(TuffColors.tagBackground)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedTodayDollars(cents: viewModel.dailySpentCents(for: user)))
                    .font(TuffFonts.panelTime())
                    .foregroundColor(TuffColors.accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 135, alignment: .trailing)

                Text("RANK \(userRank) OF \(max(allUsers.count, 1))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(TuffColors.textSecondary)
                    .tracking(0.6)
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

    private var leaguesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LEAGUES")
                .font(TuffFonts.sectionHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.15 * 12)
                .padding(.horizontal, 20)
                .padding(.top, 11)

            if viewModel.leagues.isEmpty {
                Text("Join or create a league to start comparing daily stats.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TuffColors.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 9) {
                    ForEach(viewModel.leagues) { league in
                        LeagueCardView(league: league)
                            .onTapGesture { viewModel.selectLeague(league) }
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.showCreateLeague = true
                } label: {
                    Text("+ NEW LEAGUE")
                        .font(TuffFonts.newButton())
                        .foregroundColor(.white)
                        .tracking(0.09 * 17)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(TuffColors.accent)
                        )
                }
                .buttonStyle(PressableButtonStyle())

                Button {
                    viewModel.showJoinLeague = true
                } label: {
                    Text("JOIN")
                        .font(TuffFonts.newButton())
                        .foregroundColor(TuffColors.accent)
                        .tracking(0.09 * 17)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(TuffColors.accent.opacity(0.45), lineWidth: 1.5)
                        )
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private func formattedTodayDollars(cents: Int) -> String {
        let safeCents = max(cents, 0)
        let dollars = Double(safeCents) / 100.0
        let amount = Self.currencyFormatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
        let compactAmount = amount.count > 11 ? String(amount.prefix(8)) + "..." : amount
        return "\(compactAmount) today"
    }
}
