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
    @State private var selectedTab: Tab = .feed

    private let blockDurations: [(String, TimeInterval)] = {
        var d: [(String, TimeInterval)] = [
            ("1m", 60), ("5m", 300), ("15m", 900), ("30m", 1800), ("45m", 2700)
        ]
        for h in 1...24 { d.append(("\(h)h", TimeInterval(h * 3600))) }
        return d
    }()
    // Default index = "1h" which is at index 5 (after 1m,5m,15m,30m,45m)
    @State private var selectedDurationIndex: Int = 5
    @State private var showBlockPicker = false

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
            VStack(spacing: 0) {
                if selectedTab == .feed {
                    blockBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                bottomNav
            }
        }
        .ignoresSafeArea(.keyboard)
        .familyActivityPicker(isPresented: $showBlockPicker, selection: pickerSelection)
        .onOpenURL { url in
            if url.scheme == "tuff", url.host == "block" {
                withAnimation(.easeInOut(duration: 0.22)) { selectedTab = .block }
            }
        }
    }

    // Custom binding so the setter fires block + timer immediately when picker confirms
    private var pickerSelection: Binding<FamilyActivitySelection> {
        Binding(
            get: { screenTimeManager.selectedAppsToBlock },
            set: { newValue in
                screenTimeManager.selectedAppsToBlock = newValue
                let hasApps = !newValue.applicationTokens.isEmpty || !newValue.categoryTokens.isEmpty
                if hasApps {
                    screenTimeManager.blockSelectedApps()
                    screenTimeManager.startBlockTimer(duration: blockDurations[selectedDurationIndex].1)
                }
            }
        )
    }

    // MARK: - Block Bar (Home tab only)

    private var blockBar: some View {
        let isRunning = screenTimeManager.blockTimerEndDate != nil
        let currentLabel = blockDurations[selectedDurationIndex].0
        let currentSeconds = blockDurations[selectedDurationIndex].1

        return HStack(spacing: 8) {
            if isRunning, let end = screenTimeManager.blockTimerEndDate {
                // Auto-updating countdown
                Text(timerInterval: Date()...end, countsDown: true)
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            } else {
                // − button
                Button {
                    if selectedDurationIndex > 0 { selectedDurationIndex -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            ZStack {
                                Circle().fill(Color.white.opacity(0.07)).offset(y: 2)
                                Circle().fill(Color.white.opacity(0.14))
                                Circle().fill(LinearGradient(
                                    colors: [Color.white.opacity(0.2), Color.white.opacity(0)],
                                    startPoint: .top, endPoint: .center))
                            }
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(selectedDurationIndex == 0)

                // Duration display — 3D white pill
                Text(currentLabel)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                    .frame(minWidth: 52)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 11)
                                .fill(Color(white: 0.6, opacity: 0.4))
                                .offset(y: 3)
                            RoundedRectangle(cornerRadius: 11)
                                .fill(Color.white)
                            RoundedRectangle(cornerRadius: 11)
                                .fill(LinearGradient(
                                    colors: [Color.white, Color(white: 0.92)],
                                    startPoint: .top, endPoint: .bottom))
                        }
                    )
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 3)

                // + button
                Button {
                    if selectedDurationIndex < blockDurations.count - 1 { selectedDurationIndex += 1 }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            ZStack {
                                Circle().fill(Color.white.opacity(0.07)).offset(y: 2)
                                Circle().fill(Color.white.opacity(0.14))
                                Circle().fill(LinearGradient(
                                    colors: [Color.white.opacity(0.2), Color.white.opacity(0)],
                                    startPoint: .top, endPoint: .center))
                            }
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(selectedDurationIndex == blockDurations.count - 1)
            }

            // Block Apps / Stop 3D button
            Button {
                if isRunning {
                    screenTimeManager.cancelBlockTimer()
                } else {
                    showBlockPicker = true
                }
            } label: {
                Text(isRunning ? "Stop" : "Block Apps")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isRunning ? .red : .white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isRunning ? Color.red.opacity(0.25) : TuffColors.accent.opacity(0.5))
                                .offset(y: 3)
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isRunning
                                      ? LinearGradient(colors: [Color.red.opacity(0.18), Color.red.opacity(0.18)],
                                                       startPoint: .top, endPoint: .bottom)
                                      : LinearGradient(colors: [TuffColors.accent.opacity(0.95), TuffColors.accent],
                                                       startPoint: .top, endPoint: .bottom))
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(
                                    colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                                    startPoint: .top, endPoint: .center
                                ))
                        }
                    )
                    .shadow(color: isRunning ? Color.red.opacity(0.3) : TuffColors.accent.opacity(0.4),
                            radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 12)
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
