import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct LeagueDetailSheet: View {
    let league: League
    @Environment(\.dismiss) private var dismiss

    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showEdit = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var currentUID: String { Auth.auth().currentUser?.uid ?? "" }
    private var isAdmin: Bool { league.createdBy == currentUID }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    leaderboardSection
                    payoutSection
                    actionButtons
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.white)
        .sheet(isPresented: $showEdit) {
            EditLeagueView(league: league)
        }
        .confirmationDialog(
            "Leave \"\(league.name)\"?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave League", role: .destructive) {
                Task { await leaveLeague() }
            }
        } message: {
            Text("You will be removed from this league.")
        }
        .confirmationDialog(
            "Delete \"\(league.name)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete League", role: .destructive) {
                Task { await deleteLeague() }
            }
        } message: {
            Text("This will permanently delete the league for all members.")
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
                    isCurrentUser: member.user.isCurrentUser
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

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .padding(.horizontal, 4)
            }

            if isAdmin {
                Button { showEdit = true } label: {
                    actionRow("pencil", "Edit League", textColor: .black, bg: Color(hex: "F5F5F5"))
                }

                Button { showDeleteConfirm = true } label: {
                    actionRow("trash", "Delete League", textColor: .red, bg: Color.red.opacity(0.07))
                }
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
        let docRef = db.collection("leagues").document(league.id)
        let uid = currentUID
        do {
            try await db.runTransaction { transaction, errorPointer in
                let doc: DocumentSnapshot
                do { doc = try transaction.getDocument(docRef) }
                catch let e as NSError { errorPointer?.pointee = e; return nil }
                var profiles = doc.data()?["memberProfiles"] as? [[String: Any]] ?? []
                profiles.removeAll { $0["uid"] as? String == uid }
                transaction.updateData([
                    "memberUids": FieldValue.arrayRemove([uid]),
                    "memberProfiles": profiles
                ], forDocument: docRef)
                return nil
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteLeague() async {
        isLoading = true
        defer { isLoading = false }
        let db = Firestore.firestore()
        do {
            try await db.collection("leagues").document(league.id).delete()
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
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(league: League) {
        self.league = league
        _name = State(initialValue: league.name)
        _startDate = State(initialValue: league.startDate)
        _endDate = State(initialValue: league.endDate)
        _pricePerHourCents = State(initialValue: String(league.pricePerHourCents))
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
        do {
            try await db.collection("leagues").document(league.id).updateData([
                "name": name.trimmingCharacters(in: .whitespaces),
                "startDate": Timestamp(date: startDate),
                "endDate": Timestamp(date: endDate),
                "pricePerHourCents": Int(pricePerHourCents) ?? 20
            ])
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
