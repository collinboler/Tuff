import SwiftUI
import FamilyControls

enum Tab: Int, CaseIterable {
    case feed
    case leagues
    case block
    case profile
}

struct ContentView: View {
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @StateObject private var homeViewModel = HomeViewModel()
    @State private var selectedTab: Tab = .feed

    var body: some View {
        ZStack(alignment: .bottom) {
            FeedView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .feed ? 1 : 0)
                .allowsHitTesting(selectedTab == .feed)

            LeagueView()
                .environmentObject(homeViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .leagues ? 1 : 0)
                .allowsHitTesting(selectedTab == .leagues)

            BlockView()
                .environmentObject(homeViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .block ? 1 : 0)
                .allowsHitTesting(selectedTab == .block)

            ProfileView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .profile ? 1 : 0)
                .allowsHitTesting(selectedTab == .profile)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if selectedTab == .feed {
                    breakStatusBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                bottomNav
            }
        }
        .ignoresSafeArea(.keyboard)
        .onOpenURL { url in
            if url.scheme == "tuff", url.host == "block" {
                withAnimation(.easeInOut(duration: 0.22)) { selectedTab = .block }
            }
        }
    }

    // MARK: - Break Status Bar (Home tab only)

    private var breakStatusBar: some View {
        let isOnBreak = screenTimeManager.blockTimerEndDate != nil

        return HStack(spacing: 8) {
            Image(systemName: isOnBreak ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isOnBreak ? TuffColors.accent : .white)

            if isOnBreak, let end = screenTimeManager.blockTimerEndDate {
                Text("BREAK — ")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(TuffColors.accent)
                + Text(timerInterval: Date()...end, countsDown: true)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundColor(TuffColors.accent)
            } else {
                Text("APPS LOCKED")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer()

            if isOnBreak {
                Button {
                    screenTimeManager.cancelBlockTimer()
                } label: {
                    Text("End Break")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(PressableButtonStyle())
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { selectedTab = .block }
                } label: {
                    Text("Buy Break")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(TuffColors.accent.opacity(0.5))
                                    .offset(y: 2)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(TuffColors.accent)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(
                                        colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                                        startPoint: .top, endPoint: .center
                                    ))
                            }
                        )
                        .shadow(color: TuffColors.accent.opacity(0.4), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.13, opacity: 0.96)))
        .colorScheme(.dark)
    }

    private var bottomNav: some View {
        HStack {
            navItem(.feed,    icon: "house",   filledIcon: "house.fill",  label: "Home")
            swordsNavItem()
            navItem(.block,   icon: "lock",    filledIcon: "lock.fill",   label: "Block")
            navItem(.profile, icon: "person",  filledIcon: "person.fill", label: "You")
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .padding(.top, 4)
        .background {
            ZStack(alignment: .top) {
                Color.white
                LinearGradient(
                    colors: [Color.white.opacity(0), Color.white.opacity(0.82), Color.white],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 28)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func navItem(_ tab: Tab, icon: String, filledIcon: String, label: String) -> some View {
        let isActive = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) { selectedTab = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isActive ? filledIcon : icon)
                    .font(.system(size: 20, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isActive ? TuffColors.accent : TuffColors.navInactive)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func swordsNavItem() -> some View {
        let isActive = selectedTab == .leagues
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) { selectedTab = .leagues }
        } label: {
            VStack(spacing: 3) {
                CrossedSwordsIcon()
                Text("League")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isActive ? TuffColors.accent : TuffColors.navInactive)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Crossed Swords Icon
// Tips point toward top corners; hilts/handles at bottom corners.
// Crossguard at ~72% from tip (near hilt end).

struct CrossedSwordsIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let lw: CGFloat = 1.8

            // Sword 1: tip = top-left (0.12, 0.05), hilt = bottom-right (0.88, 0.95)
            let s1tip  = CGPoint(x: w * 0.12, y: h * 0.05)
            let s1hilt = CGPoint(x: w * 0.88, y: h * 0.95)
            // Guard at 72% from tip
            let s1g = CGPoint(x: s1tip.x + 0.72 * (s1hilt.x - s1tip.x),
                              y: s1tip.y + 0.72 * (s1hilt.y - s1tip.y))
            // Perpendicular to blade direction (dx,dy)=(0.76, 0.90) → perp = (-0.90, 0.76) norm
            let len1 = sqrt(pow(s1hilt.x - s1tip.x, 2) + pow(s1hilt.y - s1tip.y, 2))
            let p1x = -(s1hilt.y - s1tip.y) / len1
            let p1y =  (s1hilt.x - s1tip.x) / len1
            let gExt: CGFloat = w * 0.13
            var b1 = Path(); b1.move(to: s1tip); b1.addLine(to: s1hilt)
            ctx.stroke(b1, with: .foreground, lineWidth: lw)
            var g1 = Path()
            g1.move(to: CGPoint(x: s1g.x + p1x * gExt, y: s1g.y + p1y * gExt))
            g1.addLine(to: CGPoint(x: s1g.x - p1x * gExt, y: s1g.y - p1y * gExt))
            ctx.stroke(g1, with: .foreground, lineWidth: lw)

            // Sword 2: tip = top-right (0.88, 0.05), hilt = bottom-left (0.12, 0.95)
            let s2tip  = CGPoint(x: w * 0.88, y: h * 0.05)
            let s2hilt = CGPoint(x: w * 0.12, y: h * 0.95)
            let s2g = CGPoint(x: s2tip.x + 0.72 * (s2hilt.x - s2tip.x),
                              y: s2tip.y + 0.72 * (s2hilt.y - s2tip.y))
            let len2 = sqrt(pow(s2hilt.x - s2tip.x, 2) + pow(s2hilt.y - s2tip.y, 2))
            let p2x = -(s2hilt.y - s2tip.y) / len2
            let p2y =  (s2hilt.x - s2tip.x) / len2
            var b2 = Path(); b2.move(to: s2tip); b2.addLine(to: s2hilt)
            ctx.stroke(b2, with: .foreground, lineWidth: lw)
            var g2 = Path()
            g2.move(to: CGPoint(x: s2g.x + p2x * gExt, y: s2g.y + p2y * gExt))
            g2.addLine(to: CGPoint(x: s2g.x - p2x * gExt, y: s2g.y - p2y * gExt))
            ctx.stroke(g2, with: .foreground, lineWidth: lw)
        }
        .frame(width: 22, height: 22)
    }
}

#Preview {
    ContentView()
        .environmentObject(ScreenTimeManager.shared)
        .environmentObject(NotificationManager.shared)
        .environmentObject(AuthViewModel())
}
