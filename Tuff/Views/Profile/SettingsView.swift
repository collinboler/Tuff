import SwiftUI
import FirebaseAuth
import FamilyControls

struct SettingsView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirm = false
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var debugLog: String = ""
    @State private var showTrackingPicker = false
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16))
                                .frame(width: 28)
                            Text("Sign Out")
                                .font(.system(size: 16))
                        }
                        .foregroundColor(.red)
                    }
                }
                .listRowBackground(Color.white)

                Section {
                    Button {
                        Task { await seedAndUploadYesterday() }
                    } label: {
                        HStack(spacing: 12) {
                            if isSyncing {
                                ProgressView().frame(width: 28)
                            } else {
                                Image(systemName: "arrow.clockwise.icloud")
                                    .font(.system(size: 16))
                                    .frame(width: 28)
                                    .foregroundColor(TuffColors.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sync Screen Time to Firestore")
                                    .font(.system(size: 16))
                                    .foregroundColor(.black)
                                if let msg = syncMessage {
                                    Text(msg)
                                        .font(.system(size: 12))
                                        .foregroundColor(TuffColors.textSecondary)
                                } else {
                                    Text("Refreshes the report then uploads to Firestore")
                                        .font(.system(size: 12))
                                        .foregroundColor(TuffColors.textSecondary)
                                }
                            }
                        }
                    }
                    .disabled(isSyncing)
                } header: {
                    Text("Developer")
                }
                .listRowBackground(Color.white)

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 16))
                            .frame(width: 28)
                            .foregroundColor(TuffColors.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Estimated Screen Time")
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                            Text("12 schedules × 23 thresholds (every 5 min)")
                                .font(.system(size: 12))
                                .foregroundColor(TuffColors.textSecondary)
                        }
                        Spacer()
                        Text(formatMinutes(screenTimeManager.estimatedTodayMinutes))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(TuffColors.accent)
                    }

                    Button { showTrackingPicker = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 16))
                                .frame(width: 28)
                                .foregroundColor(TuffColors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Change Tracked Apps")
                                    .font(.system(size: 16))
                                    .foregroundColor(.black)
                                Text(trackingLabel)
                                    .font(.system(size: 12))
                                    .foregroundColor(TuffColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(TuffColors.textSecondary)
                        }
                    }
                    .familyActivityPicker(
                        headerText: "Select all categories for complete tracking",
                        footerText: "Changes take effect after restarting monitoring",
                        isPresented: $showTrackingPicker,
                        selection: $screenTimeManager.appsToTrack
                    )
                } header: {
                    Text("Screen Time Tracking")
                } footer: {
                    Text("This is the shareable estimate pipeline. Your Stats screen still uses the exact local Apple report.")
                }
                .listRowBackground(Color.white)

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            ScreenTimeManager.clearMonitorLog()
                            screenTimeManager.estimatedTodayMinutes = 0
                            screenTimeManager.startMonitoring()
                            debugLog = buildDebugLog()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 16))
                                    .frame(width: 28)
                                    .foregroundColor(TuffColors.accent)
                                Text("Restart Monitoring")
                                    .font(.system(size: 16))
                                    .foregroundColor(.black)
                            }
                        }
                        .contentShape(Rectangle())

                        Text("auth=\(screenTimeManager.isAuthorized ? "YES" : "NO"), mon=\(screenTimeManager.isMonitoring ? "YES" : "NO")")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(TuffColors.textSecondary)

                        if !screenTimeManager.monitoringDebug.isEmpty {
                            Text(screenTimeManager.monitoringDebug)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(screenTimeManager.monitoringDebug.hasPrefix("OK") ? .green : .red)
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("Monitoring")
                }
                .listRowBackground(Color.white)

                if !debugLog.isEmpty {
                    Section {
                        Text(debugLog)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.black)
                            .textSelection(.enabled)
                    } header: {
                        Text("Debug Log (tap to copy)")
                    }
                    .listRowBackground(Color.white)
                }

                Section {
                    HStack {
                        Text("Version")
                            .foregroundColor(.black)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(TuffColors.textSecondary)
                    }
                } header: {
                    Text("About")
                }
                .listRowBackground(Color.white)
            }
            .listStyle(.insetGrouped)
            .background(Color(hex: "F5F5F5"))
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .colorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(TuffColors.accent)
                }
            }
        }
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                try? Auth.auth().signOut()
            }
        }
        .onAppear {
            screenTimeManager.refreshEstimatedMinutes()
            debugLog = buildDebugLog()
        }
    }

    private var trackingLabel: String {
        let apps = screenTimeManager.appsToTrack.applicationTokens.count
        let cats = screenTimeManager.appsToTrack.categoryTokens.count
        if apps == 0 && cats == 0 { return "No apps selected" }
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if cats > 0 { parts.append("\(cats) categor\(cats == 1 ? "y" : "ies")") }
        return parts.joined(separator: ", ")
    }

    private func buildDebugLog() -> String {
        var log = ""
        log += "=== MONITOR (file-based log) ===\n"
        log += "schedules: \(screenTimeManager.monitoringDebug)\n"
        log += "estimated today: \(screenTimeManager.estimatedTodayMinutes)m\n\n"
        log += ScreenTimeManager.readMonitorLog()
        return log
    }

    private func seedAndUploadYesterday() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSyncing = true
        syncMessage = nil
        debugLog = ""

        screenTimeManager.refreshEstimatedMinutes()
        let log = buildDebugLog()
        print("[Sync Debug]\n\(log)")

        screenTimeManager.syncScreenTimeToFirestore(uid: uid)

        let estMin = ScreenTimeManager.readEstimatedMinutesFromLog()
        syncMessage = "estimated: \(estMin)m"
        debugLog = log
        isSyncing = false
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)h \(String(format: "%02d", m))m"
    }
}
