import SwiftUI

enum Tab: Int, CaseIterable {
    case stats
    case home
    case profile
}

struct ContentView: View {
    @State private var selectedTab: Tab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            StatsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .stats ? 1 : 0)
                .allowsHitTesting(selectedTab == .stats)

            HomeView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .home ? 1 : 0)
                .allowsHitTesting(selectedTab == .home)

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

    // Compact bottom nav with a soft white fade.
    private var bottomNav: some View {
        HStack {
            navItem(.stats, icon: "chart.xyaxis.line", isActive: selectedTab == .stats)
            navItem(.home, icon: "house", isActive: selectedTab == .home)
            navItem(.profile, icon: "person", isActive: selectedTab == .profile)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .padding(.top, 6)
        .background {
            ZStack(alignment: .top) {
                Color.white
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.82),
                        Color.white
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func navItem(_ tab: Tab, icon: String, isActive: Bool) -> some View {
        let filledIcon: String = {
            switch tab {
            case .stats: return "chart.xyaxis.line"
            case .home: return "house.fill"
            case .profile: return "person.fill"
            }
        }()
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                selectedTab = tab
            }
        } label: {
            Image(systemName: isActive ? filledIcon : icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isActive ? TuffColors.accent : TuffColors.navInactive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ScreenTimeManager.shared)
        .environmentObject(NotificationManager.shared)
}
