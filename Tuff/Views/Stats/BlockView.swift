import SwiftUI
import FamilyControls
import FirebaseAuth

/// Screen Time “block” hub: pick distracting apps, earn limited unlocks via challenges.
struct BlockView: View {
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @EnvironmentObject var homeViewModel: HomeViewModel

    @State private var pickerSelection = FamilyActivitySelection()
    @State private var showBlockedPicker = false

    @State private var challengeKind = UnlockChallengeKind.loadSaved()
    @State private var selectedUnlockMinutes = 15

    @State private var showChallengeFlow = false
    @State private var showFlashcardEditor = false

    @State private var isEndingUnlock = false

    private let unlockOptions: [(label: String, minutes: Int)] = [
        ("5 min", 5),
        ("10 min", 10),
        ("15 min", 15),
        ("20 min", 20),
        ("30 min", 30),
        ("45 min", 45)
    ]

    private var hasBlockingSelections: Bool { screenTimeManager.blockedAppSelection.tuffHasBlockingSelections }

    private var blockingSubtitle: String {
        let s = screenTimeManager.blockedAppSelection
        let a = s.applicationTokens.count
        let c = s.categoryTokens.count
        guard a > 0 || c > 0 else { return "" }
        if a > 0 && c > 0 { return "\(a) apps · \(c) categories shielded" }
        if c > 0 { return "\(c) categor\(c == 1 ? "y" : "ies") shielded" }
        return "\(a) app\(a == 1 ? "" : "s") shielded"
    }

    private var isOnUnlockSession: Bool { screenTimeManager.blockTimerEndDate != nil }
    private var activeLeagues: [League] { homeViewModel.leagues.filter { $0.isActive } }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    if isOnUnlockSession {
                        unlockSessionCard
                    } else {
                        idleHeader
                    }

                    configurationCard

                    if !isOnUnlockSession {
                        startChallengeCard
                    }

                    Text("Up to Screen Time limits (roughly 50 app and category tokens combined). You can choose individual apps or whole categories—category picks count even when the app-token count stayed at zero.")
                        .font(.system(size: 12))
                        .foregroundColor(TuffColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.vertical, 28)
            }
        }
        .sheet(isPresented: $showBlockedPicker) {
            blockedAppsPickerSheet
        }
        .sheet(isPresented: $showFlashcardEditor) {
            UnlockFlashcardEditorSheet()
        }
        .fullScreenCover(isPresented: $showChallengeFlow) {
            ChallengeGateView(
                preferredKind: challengeKind,
                unlockMinutes: selectedUnlockMinutes,
                onDismiss: { showChallengeFlow = false },
                onEarnedUnlock: { showChallengeFlow = false }
            )
            .environmentObject(screenTimeManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tuffOpenChallengeGate)) { _ in
            showChallengeFlow = true
        }
        .onChange(of: showBlockedPicker) { _, open in
            if open { pickerSelection = screenTimeManager.blockedAppSelection }
        }
    }

    // MARK: - Sections

    private var idleHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 44))
                .foregroundColor(.black)
            Text("FOCUSED BLOCKING")
                .font(.system(size: 22, weight: .black).width(.condensed))
                .tracking(1)
            Text("Shield only the temptations you picked. Earn time off with a challenge.")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }

    private var unlockSessionCard: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 42))
                    .foregroundColor(TuffColors.accent)
                Text("UNLOCK ACTIVE")
                    .font(.system(size: 20, weight: .heavy).width(.condensed))
                if let end = screenTimeManager.blockTimerEndDate {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .font(.system(size: 40, weight: .black, design: .monospaced).monospacedDigit())
                        .foregroundColor(TuffColors.accent)
                }
                Text("Blocked apps open normally until this timer ends.")
                    .font(.system(size: 13))
                    .foregroundColor(TuffColors.textSecondary)
            }

            Button {
                guard !isEndingUnlock else { return }
                isEndingUnlock = true
                let uid = Auth.auth().currentUser?.uid ?? ""
                let leagues = activeLeagues
                Task {
                    await screenTimeManager.cancelBreakEarly(uid: uid, leagues: leagues)
                    await MainActor.run { isEndingUnlock = false }
                }
            } label: {
                HStack {
                    if isEndingUnlock { ProgressView().tint(.white) }
                    else {
                        Image(systemName: "lock.fill")
                        Text("End unlock early")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.red.opacity(0.88)))
            }
            .disabled(isEndingUnlock)
            .padding(.horizontal, 24)
        }
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("APPS TO BLOCK")
            Button {
                showBlockedPicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hasBlockingSelections ? blockingSubtitle : "Choose distracting apps or categories.")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                        Text("Uses the private Apple picker — Tuff never sees app names.")
                            .font(.system(size: 12))
                            .foregroundColor(TuffColors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(TuffColors.accent)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "F6F6F6")))
            }

            sectionHeader("DEFAULT CHALLENGE")
            Picker("Challenge", selection: $challengeKind) {
                ForEach(UnlockChallengeKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .tint(.black)
            .onChange(of: challengeKind) { _, new in new.savePreferred() }

            Text(challengeKind.subtitle)
                .font(.system(size: 12))
                .foregroundColor(TuffColors.textSecondary)

            if challengeKind == .flashcardQuiz {
                Button {
                    showFlashcardEditor = true
                } label: {
                    Label("Edit flashcard deck", systemImage: "rectangle.on.rectangle.angled")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TuffColors.accent)
                }
            }

            sectionHeader("UNLOCK LENGTH")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(unlockOptions, id: \.minutes) { opt in
                        let selected = selectedUnlockMinutes == opt.minutes
                        Button {
                            selectedUnlockMinutes = opt.minutes
                        } label: {
                            Text(opt.label)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(selected ? .black : TuffColors.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selected ? TuffColors.accent : Color(hex: "EEEEEE"))
                                )
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 20)
    }

    private var startChallengeCard: some View {
        VStack(spacing: 12) {
            Button {
                guard hasBlockingSelections else { return }
                screenTimeManager.saveBlockedSelection(screenTimeManager.blockedAppSelection)
                screenTimeManager.blockSelectedApps()
                showChallengeFlow = true
            } label: {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("Start challenge for unlock")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(hasBlockingSelections ? .black : Color.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(hasBlockingSelections ? TuffColors.accent : Color.black.opacity(0.18))
                )
            }
            .disabled(!hasBlockingSelections)

            if !hasBlockingSelections {
                Text("Pick at least one app or category in the blocker list — category picks still count.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.orange.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 22)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(TuffFonts.sectionHeader())
            .foregroundColor(TuffColors.textSecondary)
            .tracking(0.15 * 12)
    }

    private var blockedAppsPickerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Anything you select here will stay blocked until you finish a challenge and use your unlock timer.")
                    .font(TuffFonts.caption(12))
                    .foregroundColor(TuffColors.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                FamilyActivityPicker(selection: $pickerSelection)
            }
            .navigationTitle("Blocked apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showBlockedPicker = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        screenTimeManager.saveBlockedSelection(pickerSelection)
                        screenTimeManager.blockSelectedApps()
                        showBlockedPicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
