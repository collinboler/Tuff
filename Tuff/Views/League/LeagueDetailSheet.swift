import SwiftUI
import FamilyControls
import FirebaseAuth
import FirebaseFirestore

struct LeagueDetailSheet: View {
    let league: League
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var screenTimeManager = ScreenTimeManager.shared

    @State private var showLeaveConfirm = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showEditLeague = false
    @State private var showAllowedAppsPicker = false

    private var currentUID: String { Auth.auth().currentUser?.uid ?? "" }
    private var isCreator: Bool { league.createdBy == currentUID }

    var body: some View {
        Group {
            if league.hasEnded {
                // Once a league has ended, always show the results screen
                // instead of the in-progress leaderboard/leave UI.
                LeagueEndedView(league: league) { dismiss() }
            } else {
                activeLeagueBody
            }
        }
    }

    private var activeLeagueBody: some View {
        VStack(spacing: 0) {
            headerSection

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    leaderboardSection
                    payoutSection
                    if league.allowedAppsCount > 0 || !league.allowedApps.isEmpty {
                        allowedAppsSection
                    }
                    actionButtons
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.white)
        .sheet(isPresented: $showEditLeague) {
            EditLeagueView(league: league)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAllowedAppsPicker) {
            AllowedAppsPickerSheet(
                allowedAppsCount: max(league.allowedAppsCount, league.allowedApps.count),
                selection: $screenTimeManager.allowedAppSelection
            ) { selection in
                screenTimeManager.saveAllowedSelection(selection)
            }
        }
        .confirmationDialog(
            "Leave \"\(league.name)\"?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave & Forfeit", role: .destructive) {
                Task { await leaveLeague() }
            }
        } message: {
            Text("Your spent amount stays in the pool, but you'll be marked DQ'd and ineligible to win.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(league.name.uppercased())
                    .font(TuffFonts.modalTitle())
                    .foregroundColor(.black)
                    .tracking(0.05 * 24)

                HStack(spacing: 10) {
                    Text(league.dateRangeText)
                        .font(TuffFonts.caption(12))
                        .foregroundColor(TuffColors.textSecondary)

                    Text(String(format: "$%.2f pool", league.poolDollars))
                        .font(TuffFonts.modalPot())
                        .foregroundColor(TuffColors.accent)

                    Text("·  \(league.pricePerHourCents)¢/hr")
                        .font(TuffFonts.caption(12))
                        .foregroundColor(TuffColors.textSecondary)
                }

                if !league.inviteCode.isEmpty {
                    Button {
                        UIPasteboard.general.string = league.inviteCode
                    } label: {
                        HStack(spacing: 6) {
                            Text("CODE: \(league.inviteCode)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(TuffColors.accent)
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundColor(TuffColors.accent)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(TuffColors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if isCreator {
                    Button {
                        showEditLeague = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(TuffColors.modalCloseText)
                            .frame(width: 30, height: 30)
                            .background(TuffColors.modalCloseBg)
                            .clipShape(Circle())
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text("✕")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(TuffColors.modalCloseText)
                        .frame(width: 30, height: 30)
                        .background(TuffColors.modalCloseBg)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Leaderboard

    private var leaderboardSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(league.sortedMembers.enumerated()), id: \.element.id) { index, member in
                LeaderboardRowView(
                    rank: index + 1,
                    member: member,
                    isCurrentUser: member.user.isCurrentUser,
                    joinedLate: league.isLateJoiner(member)
                )

                if index < league.sortedMembers.count - 1 {
                    Divider()
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Prize Pool

    private var payoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRIZE POOL")
                .font(TuffFonts.payoutHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.14 * 11)

            ForEach(league.payoutBreakdown, id: \.place) { payout in
                HStack {
                    Text(payout.place)
                        .font(TuffFonts.body(13))
                        .foregroundColor(Color(hex: "555555"))

                    Spacer()

                    Text(payout.amount)
                        .font(TuffFonts.payoutAmount())
                        .foregroundColor(TuffColors.accent)
                }
            }

            Text("Spend the least on breaks to win the entire pool.")
                .font(TuffFonts.caption(11))
                .foregroundColor(TuffColors.textSecondary)
        }
        .padding(20)
        .background(TuffColors.payoutBg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TuffColors.divider)
                .frame(height: 1)
        }
        .padding(.top, 8)
    }

    // MARK: - Allowed Apps

    private var allowedAppsSection: some View {
        let total = max(league.allowedAppsCount, league.allowedApps.count)
        let myCount = screenTimeManager.allowedAppSelection.applicationTokens.count
        return VStack(alignment: .leading, spacing: 10) {
            Text("ALLOWED APPS")
                .font(TuffFonts.payoutHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.14 * 11)

            HStack(spacing: 6) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 12))
                    .foregroundColor(TuffColors.accent)
                Text("\(total) app\(total == 1 ? "" : "s") allowed by this league")
                    .font(TuffFonts.caption(12))
                    .foregroundColor(TuffColors.textSecondary)
            }

            Button {
                showAllowedAppsPicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: myCount == 0 ? "lock.open" : "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(myCount == 0 ? TuffColors.textSecondary : TuffColors.accent)

                    if myCount == 0 {
                        Text("Configure My Allowed Apps")
                            .font(TuffFonts.body(13))
                            .foregroundColor(TuffColors.textSecondary)
                    } else {
                        Text("\(myCount) app\(myCount == 1 ? "" : "s") allowed on this device")
                            .font(TuffFonts.body(13))
                            .foregroundColor(TuffColors.accent)
                    }

                    Spacer()

                    Text(myCount == 0 ? "Set Up" : "Change")
                        .font(TuffFonts.caption(12))
                        .foregroundColor(TuffColors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(TuffColors.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(myCount == 0 ? TuffColors.tagBackground : TuffColors.accent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if myCount == 0 {
                Text("Tap Set Up to choose which apps stay accessible while you're blocked.")
                    .font(TuffFonts.caption(11))
                    .foregroundColor(TuffColors.textSecondary)
            }
        }
        .padding(20)
        .background(TuffColors.payoutBg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TuffColors.divider)
                .frame(height: 1)
        }
        .padding(.top, 0)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .padding(.horizontal, 4)
            }

            Button { showLeaveConfirm = true } label: {
                actionRow("rectangle.portrait.and.arrow.right", "Leave League",
                          textColor: .red, bg: Color.red.opacity(0.07))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .disabled(isLoading)
    }

    private func actionRow(_ icon: String, _ title: String, textColor: Color, bg: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .foregroundColor(textColor)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Firestore Actions

    private func leaveLeague() async {
        isLoading = true
        defer { isLoading = false }
        let db = Firestore.firestore()
        let uid = currentUID
        do {
            // Keep the member in the league so their score counts toward the pool,
            // but add them to dqdUids so they're ineligible to win. Also remove
            // them from the Firestore query filter so the league stops showing for them.
            try await db.collection("leagues").document(league.id).updateData([
                "memberUids": FieldValue.arrayRemove([uid]),
                "dqdUids": FieldValue.arrayUnion([uid])
            ])
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

// MARK: - Edit League Sheet

struct EditLeagueView: View {
    let league: League
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var pricePerHourCents: String
    @State private var allowedAppSelection: FamilyActivitySelection
    @State private var showAppPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(league: League) {
        self.league = league
        _name = State(initialValue: league.name)
        _startDate = State(initialValue: league.startDate)
        _endDate = State(initialValue: league.endDate)
        _pricePerHourCents = State(initialValue: String(league.pricePerHourCents))
        // Start with the currently saved local selection
        let saved = ScreenTimeManager.shared.allowedAppSelection
        _allowedAppSelection = State(initialValue: saved)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("LEAGUE NAME")
                        TextField("League name", text: $name)
                            .font(TuffFonts.body(14))
                            .padding(12)
                            .background(TuffColors.tagBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Dates
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel("START")
                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel("END")
                            DatePicker("", selection: $endDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }

                    // Price per hour
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("PRICE PER HOUR (¢)")
                        HStack {
                            TextField("20", text: $pricePerHourCents)
                                .font(TuffFonts.leagueCardPot())
                                .keyboardType(.numberPad)
                            Text("¢ / hr")
                                .font(TuffFonts.leagueCardPot())
                                .foregroundColor(TuffColors.textSecondary)
                        }
                        .padding(12)
                        .background(TuffColors.tagBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Allowed apps
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("ALLOWED APPS")
                        Text("Apps that stay accessible even while blocking is active.")
                            .font(TuffFonts.caption(12))
                            .foregroundColor(TuffColors.textSecondary)

                        Button {
                            showAppPicker = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: allowedAppSelection.applicationTokens.isEmpty
                                      ? "lock.open" : "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(allowedAppSelection.applicationTokens.isEmpty
                                                     ? TuffColors.textSecondary : TuffColors.accent)

                                if allowedAppSelection.applicationTokens.isEmpty {
                                    Text("Select Allowed Apps")
                                        .font(TuffFonts.body(14))
                                        .foregroundColor(TuffColors.textSecondary)
                                } else {
                                    Text("\(allowedAppSelection.applicationTokens.count) app\(allowedAppSelection.applicationTokens.count == 1 ? "" : "s") selected")
                                        .font(TuffFonts.body(14))
                                        .foregroundColor(TuffColors.accent)
                                }

                                Spacer()

                                Text(allowedAppSelection.applicationTokens.isEmpty ? "Choose" : "Change")
                                    .font(TuffFonts.caption(12))
                                    .foregroundColor(TuffColors.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(TuffColors.accent.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .padding(12)
                            .background(TuffColors.tagBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Text("Suggestions: " + AllowedApp.suggestions.prefix(5).map { $0.displayName }.joined(separator: ", "))
                            .font(TuffFonts.caption(11))
                            .foregroundColor(TuffColors.textSecondary)
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }

                    // Save button
                    Button {
                        Task { await saveChanges() }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(name.trimmingCharacters(in: .whitespaces).isEmpty
                                      ? Color(hex: "E0E0E0") : TuffColors.accent)
                                .frame(height: 54)
                            if isSaving {
                                ProgressView().tint(.black)
                            } else {
                                Text("SAVE CHANGES")
                                    .font(TuffFonts.newButton())
                                    .foregroundColor(.black)
                                    .tracking(0.09 * 17)
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .background(Color.white)
            .navigationTitle("Edit League")
            .navigationBarTitleDisplayMode(.large)
            .colorScheme(.light)
            .sheet(isPresented: $showAppPicker) {
                NavigationStack {
                    FamilyActivityPicker(selection: $allowedAppSelection)
                        .navigationTitle("Allowed Apps")
                        .navigationBarTitleDisplayMode(.inline)
                        .colorScheme(.light)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showAppPicker = false }
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(TuffColors.accent)
                            }
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(TuffColors.textSecondary)
                }
            }
        }
    }

    private func saveChanges() async {
        isSaving = true
        errorMessage = nil
        let db = Firestore.firestore()
        let parsedPricePerHourCents = Int(pricePerHourCents) ?? 20
        do {
            try await db.collection("leagues").document(league.id).updateData([
                "name": name.trimmingCharacters(in: .whitespaces),
                "startDate": Timestamp(date: startDate),
                "endDate": Timestamp(date: endDate),
                "pricePerHourCents": parsedPricePerHourCents,
                "allowedAppsCount": allowedAppSelection.applicationTokens.count
            ])
            // Persist the token selection locally so blocking respects it immediately
            await ScreenTimeManager.shared.saveAllowedSelection(allowedAppSelection)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(TuffFonts.sectionHeader())
            .foregroundColor(TuffColors.textSecondary)
            .tracking(0.15 * 12)
    }
}

// MARK: - Allowed Apps Picker Sheet

struct AllowedAppsPickerSheet: View {
    let allowedAppsCount: Int
    @Binding var selection: FamilyActivitySelection
    let onSave: (FamilyActivitySelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var localSelection: FamilyActivitySelection

    init(allowedAppsCount: Int,
         selection: Binding<FamilyActivitySelection>,
         onSave: @escaping (FamilyActivitySelection) -> Void) {
        self.allowedAppsCount = allowedAppsCount
        self._selection = selection
        self.onSave = onSave
        _localSelection = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The league creator has allowed \(allowedAppsCount) app\(allowedAppsCount == 1 ? "" : "s"). Select which ones should stay unblocked on your device.")
                        .font(TuffFonts.caption(12))
                        .foregroundColor(TuffColors.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }

                FamilyActivityPicker(selection: $localSelection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.white)
            .navigationTitle("Allowed Apps")
            .navigationBarTitleDisplayMode(.inline)
            .colorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(TuffColors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(localSelection)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TuffColors.accent)
                }
            }
        }
    }
}

// MARK: - Flow Layout (wrapping HStack)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
