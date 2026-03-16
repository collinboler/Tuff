import SwiftUI

enum Tab: Int, CaseIterable {
    case feed
    case leagues
    case block
    case profile
}

struct ContentView: View {
    @State private var selectedTab: Tab = .feed

    var body: some View {
        ZStack(alignment: .bottom) {
            FeedView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .feed ? 1 : 0)
                .allowsHitTesting(selectedTab == .feed)

            LeagueView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .leagues ? 1 : 0)
                .allowsHitTesting(selectedTab == .leagues)

            BlockView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .block ? 1 : 0)
                .allowsHitTesting(selectedTab == .block)

            ProfileView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .profile ? 1 : 0)
                .allowsHitTesting(selectedTab == .profile)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomNav
        }
        .ignoresSafeArea(.keyboard)
    }

    private var bottomNav: some View {
        HStack {
            navItem(.feed,    icon: "house",   filledIcon: "house.fill")
            swordsNavItem()
            navItem(.block,   icon: "lock",    filledIcon: "lock.fill")
            navItem(.profile, icon: "person",  filledIcon: "person.fill")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .padding(.top, 6)
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

    private func navItem(_ tab: Tab, icon: String, filledIcon: String) -> some View {
        let isActive = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) { selectedTab = tab }
        } label: {
            Image(systemName: isActive ? filledIcon : icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isActive ? TuffColors.accent : TuffColors.navInactive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func swordsNavItem() -> some View {
        let isActive = selectedTab == .leagues
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) { selectedTab = .leagues }
        } label: {
            CrossedSwordsIcon()
                .foregroundColor(isActive ? TuffColors.accent : TuffColors.navInactive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Crossed Swords Icon

struct CrossedSwordsIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let lw: CGFloat = 2.0

            // Sword 1 blade: top-left → bottom-right
            var b1 = Path()
            b1.move(to: CGPoint(x: w * 0.08, y: h * 0.08))
            b1.addLine(to: CGPoint(x: w * 0.92, y: h * 0.92))
            ctx.stroke(b1, with: .foreground, lineWidth: lw)

            // Sword 1 crossguard (perpendicular, ~30% from handle)
            var g1 = Path()
            g1.move(to: CGPoint(x: w * 0.20, y: h * 0.36))
            g1.addLine(to: CGPoint(x: w * 0.36, y: h * 0.20))
            ctx.stroke(g1, with: .foreground, lineWidth: lw)

            // Sword 2 blade: top-right → bottom-left
            var b2 = Path()
            b2.move(to: CGPoint(x: w * 0.92, y: h * 0.08))
            b2.addLine(to: CGPoint(x: w * 0.08, y: h * 0.92))
            ctx.stroke(b2, with: .foreground, lineWidth: lw)

            // Sword 2 crossguard
            var g2 = Path()
            g2.move(to: CGPoint(x: w * 0.64, y: h * 0.20))
            g2.addLine(to: CGPoint(x: w * 0.80, y: h * 0.36))
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
