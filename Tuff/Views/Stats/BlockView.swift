import SwiftUI
import FamilyControls
import ManagedSettings

struct BlockView: View {
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @State private var showAppPicker = false

    private let blockDurations: [(String, TimeInterval)] = {
        var d: [(String, TimeInterval)] = [
            ("1m", 60), ("5m", 300), ("15m", 900), ("30m", 1800), ("45m", 2700)
        ]
        for h in 1...24 { d.append(("\(h)h", TimeInterval(h * 3600))) }
        return d
    }()
    @State private var selectedDurationIndex: Int = 5

    private var isBlocking: Bool { screenTimeManager.isActivelyBlocking }
    private var isTimerRunning: Bool { screenTimeManager.blockTimerEndDate != nil }

    private var appCount: Int {
        screenTimeManager.selectedAppsToBlock.applicationTokens.count +
        screenTimeManager.selectedAppsToBlock.categoryTokens.count
    }

    // Custom binding — fires block + timer on picker confirm, no double-call
    private var blockPickerBinding: Binding<FamilyActivitySelection> {
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

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Text(isBlocking
                     ? "Blocking \(appCount) app\(appCount == 1 ? "" : "s")"
                     : "No apps blocked")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "999999"))

                // Main 3D pill button
                Button {
                    if isBlocking {
                        screenTimeManager.cancelBlockTimer()
                    } else {
                        showAppPicker = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isBlocking ? "lock.open" : "lock.fill")
                            .font(.system(size: 17, weight: .semibold))
                        Text(isBlocking ? "Unblock Apps" : "Block Apps")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(isBlocking ? Color.red.opacity(0.5) : TuffColors.accent.opacity(0.55))
                                .offset(y: 4)
                            RoundedRectangle(cornerRadius: 18)
                                .fill(isBlocking
                                      ? LinearGradient(colors: [Color.red.opacity(0.85), Color.red.opacity(0.75)],
                                                       startPoint: .top, endPoint: .bottom)
                                      : LinearGradient(colors: [TuffColors.accent.opacity(0.95), TuffColors.accent],
                                                       startPoint: .top, endPoint: .bottom))
                            RoundedRectangle(cornerRadius: 18)
                                .fill(LinearGradient(
                                    colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                                    startPoint: .top, endPoint: .center
                                ))
                        }
                    )
                    .shadow(color: isBlocking ? Color.red.opacity(0.4) : TuffColors.accent.opacity(0.45),
                            radius: 12, x: 0, y: 6)
                }
                .padding(.horizontal, 40)
                .buttonStyle(PressableButtonStyle())

                timerStepper

                Spacer()
            }
        }
        .familyActivityPicker(isPresented: $showAppPicker, selection: blockPickerBinding)
    }

    // MARK: - Timer Stepper (no Start/Stop button — timer auto-starts with block)

    private var timerStepper: some View {
        let currentLabel = blockDurations[selectedDurationIndex].0

        return HStack(spacing: 8) {
            // Hide stepper buttons while timer is running
            if !isTimerRunning {
                Button {
                    if selectedDurationIndex > 0 { selectedDurationIndex -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            ZStack {
                                Circle().fill(Color(white: 0.13, opacity: 0.96)).offset(y: 2)
                                Circle().fill(Color(white: 0.22, opacity: 0.96))
                                Circle().fill(LinearGradient(
                                    colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                                    startPoint: .top, endPoint: .center))
                            }
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(selectedDurationIndex == 0)
            }

            // Pill: countdown when running, duration label when idle
            Group {
                if isTimerRunning, let end = screenTimeManager.blockTimerEndDate {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundColor(TuffColors.accent)
                } else {
                    Text(currentLabel)
                        .font(.system(size: 16, weight: .bold).monospacedDigit())
                        .foregroundColor(.black)
                }
            }
            .frame(minWidth: 80)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(isTimerRunning ? TuffColors.accent.opacity(0.15) : Color(white: 0.75, opacity: 0.5))
                        .offset(y: 3)
                    RoundedRectangle(cornerRadius: 11)
                        .fill(isTimerRunning
                              ? LinearGradient(colors: [TuffColors.accent.opacity(0.12), TuffColors.accent.opacity(0.08)],
                                               startPoint: .top, endPoint: .bottom)
                              : LinearGradient(colors: [Color.white, Color(white: 0.92)],
                                               startPoint: .top, endPoint: .bottom))
                }
            )
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 3)

            if !isTimerRunning {
                Button {
                    if selectedDurationIndex < blockDurations.count - 1 { selectedDurationIndex += 1 }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            ZStack {
                                Circle().fill(Color(white: 0.13, opacity: 0.96)).offset(y: 2)
                                Circle().fill(Color(white: 0.22, opacity: 0.96))
                                Circle().fill(LinearGradient(
                                    colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                                    startPoint: .top, endPoint: .center))
                            }
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(selectedDurationIndex == blockDurations.count - 1)
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Press-down animation

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
