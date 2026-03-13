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
            Group {
                switch selectedTab {
                case .stats:
                    StatsView()
                case .home:
                    HomeView()
                case .profile:
                    ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomNav
        }
        .ignoresSafeArea(.keyboard)
    }

    // Matches the HTML: 60px nav, #fff bg, 1px top border #EBEBEB
    private var bottomNav: some View {
        HStack {
            navItem(.stats, icon: "chart.xyaxis.line", isActive: selectedTab == .stats)
            navItem(.home, icon: "house", isActive: selectedTab == .home)
            navItem(.profile, icon: "person", isActive: selectedTab == .profile)
        }
        .frame(height: 60)
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TuffColors.divider)
                .frame(height: 1)
        }
    }

    private func navItem(_ tab: Tab, icon: String, isActive: Bool) -> some View {
        let filledIcon: String = {
            switch tab {
            case .stats: return "waveform.path.ecg"
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
                .font(.system(size: 22, weight: .medium))
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
