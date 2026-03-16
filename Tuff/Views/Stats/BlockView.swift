import SwiftUI
import FamilyControls
import ManagedSettings

struct BlockView: View {
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @State private var showAppPicker = false
    @State private var isBlocking = false

    private var appCount: Int {
        screenTimeManager.selectedAppsToBlock.applicationTokens.count +
        screenTimeManager.selectedAppsToBlock.categoryTokens.count
    }

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [Color(hex: "1A1A1A"), Color(hex: "0D0D0D")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // Lock icon
                Image(systemName: isBlocking ? "lock.fill" : "lock.open")
                    .font(.system(size: 52, weight: .light))
                    .foregroundColor(isBlocking ? TuffColors.accent : Color.white.opacity(0.3))

                Text(isBlocking ? "Blocking \(appCount) app\(appCount == 1 ? "" : "s")" : "Not blocking anything")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.45))

                Spacer()

                // Main pill buttons
                VStack(spacing: 12) {
                    // Select / Change apps button
                    Button { showAppPicker = true } label: {
                        HStack(spacing: 12) {
                            if isBlocking {
                                // App token icons
                                ForEach(Array(screenTimeManager.selectedAppsToBlock.applicationTokens.prefix(3)), id: \.self) { token in
                                    Label(token)
                                        .labelStyle(.iconOnly)
                                        .scaleEffect(0.75)
                                        .frame(width: 24, height: 24)
                                }
                                if appCount > 3 {
                                    Text("+\(appCount - 3)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            Text(isBlocking ? "Change Apps" : "Block Apps")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(isBlocking ? 0.12 : 0.15))
                                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
                        )
                    }

                    // Unblock button (only when blocking)
                    if isBlocking {
                        Button {
                            screenTimeManager.unblockAllApps()
                            isBlocking = false
                        } label: {
                            Text("Remove Blocks")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.red.opacity(0.9))
                                .padding(.horizontal, 28)
                                .padding(.vertical, 16)
                                .background(
                                    Capsule()
                                        .fill(Color.red.opacity(0.12))
                                        .overlay(Capsule().stroke(Color.red.opacity(0.15), lineWidth: 1))
                                )
                        }
                    }
                }
                .padding(.bottom, 52)
            }
        }
        .familyActivityPicker(
            isPresented: $showAppPicker,
            selection: $screenTimeManager.selectedAppsToBlock
        )
        .onChange(of: screenTimeManager.selectedAppsToBlock) { _, newValue in
            let hasApps = !newValue.applicationTokens.isEmpty || !newValue.categoryTokens.isEmpty
            if hasApps {
                screenTimeManager.blockSelectedApps()
                isBlocking = true
            }
        }
    }
}
