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
    @State private var showTrackPicker = false

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
                    Button {
                        showTrackPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "eye")
                                .font(.system(size: 16))
                                .frame(width: 28)
                                .foregroundColor(TuffColors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Select Apps to Track")
                                    .font(.system(size: 16))
                                    .foregroundColor(.black)
                                let t = screenTimeManager.appsToTrack
                                let count = t.applicationTokens.count + t.categoryTokens.count
                                Text(count > 0 ? "Tracking \(count) app/categories" : "No apps selected — tap to choose")
                                    .font(.system(size: 12))
                                    .foregroundColor(count > 0 ? .green : TuffColors.textSecondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                } header: {
                    Text("Screen Time Tracking")
                } footer: {
                    Text("Pick ALL the apps and categories you use so Tuff can track your total screen time for leagues.")
                }
                .listRowBackground(Color.white)

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
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
        .familyActivityPicker(
            isPresented: $showTrackPicker,
            selection: $screenTimeManager.appsToTrack
        )
        .onChange(of: screenTimeManager.appsToTrack) { _ in
            screenTimeManager.startMonitoring()
            debugLog = buildDebugLog()
        }
    }

    private func buildDebugLog() -> String {
        let ud = UserDefaults(suiteName: "group.com.collinboler.tuff")
        ud?.synchronize()

        var log = ""

        let t = screenTimeManager.appsToTrack
        log += "TRACKING: \(t.applicationTokens.count) apps, \(t.categoryTokens.count) categories, \(t.webDomainTokens.count) web domains\n"
        log += "monitoring: \(screenTimeManager.monitoringDebug)\n"

        let monitorTs = ud?.double(forKey: "monitorLastStarted") ?? 0
        if monitorTs > 0 {
            let age = Date().timeIntervalSince1970 - monitorTs
            log += "MONITOR intervalDidStart: \(Int(age))s ago\n"
        } else {
            log += "MONITOR intervalDidStart: never\n"
        }

        let thresholdTs = ud?.double(forKey: "lastThresholdFired") ?? 0
        if thresholdTs > 0 {
            let age = Date().timeIntervalSince1970 - thresholdTs
            let name = ud?.string(forKey: "lastThresholdName") ?? "?"
            log += "LAST THRESHOLD: \(name), \(Int(age))s ago\n"
        } else {
            log += "LAST THRESHOLD: none fired yet\n"
        }

        let thresholdCount = ud?.integer(forKey: "thresholdFireCount") ?? 0
        log += "THRESHOLD FIRE COUNT: \(thresholdCount)\n"
        let nextThreshold = ud?.integer(forKey: "nextThresholdMinutes") ?? 0
        if nextThreshold > 0 {
            log += "NEXT THRESHOLD: \(nextThreshold)m\n"
        }

        let rawToday = ud?.double(forKey: "todayScreenTime") ?? 0
        log += "todayScreenTime: \(Int(rawToday/60))m (\(Int(rawToday))s)\n"

        let lastUpdated = ud?.object(forKey: "screenTimeLastUpdated") as? Date
        log += "lastUpdated: \(lastUpdated?.description ?? "nil")\n"

        let storeHistory = TuffSharedStore.dailyHistory()
        log += "history: \(storeHistory.count) days\n"
        for r in storeHistory.prefix(5) {
            log += "  \(Self.dateFmt.string(from: r.date)): \(Int(r.totalSeconds/60))m\n"
        }

        return log
    }

    private func seedAndUploadYesterday() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSyncing = true
        syncMessage = nil
        debugLog = ""

        let log = buildDebugLog()
        print("[Sync Debug]\n\(log)")

        let storeToday = TuffSharedStore.todayScreenTime() ?? 0
        let storeHistory = TuffSharedStore.dailyHistory()
        let storeApps = TuffSharedStore.appBreakdown()
        screenTimeManager.syncScreenTimeToFirestore(uid: uid)

        syncMessage = "today=\(Int(storeToday/60))m, \(storeHistory.count) days, \(storeApps.count) apps"
        debugLog = log
        isSyncing = false
    }
}
