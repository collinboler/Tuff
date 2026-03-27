import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CreateLeagueView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var leagueName = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()
    @State private var pricePerHourCents = "20"
    @State private var inviteCode = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    nameField
                    datesRow
                    pricePerHourField
                    inviteSection
                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                    }
                    createButton
                }
                .padding(20)
            }
            .background(Color.white)
            .navigationTitle("New League")
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

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("LEAGUE NAME")
            TextField("e.g. Work Squad", text: $leagueName)
                .font(TuffFonts.body(14))
                .padding(12)
                .background(TuffColors.tagBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Dates

    private var datesRow: some View {
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
    }

    // MARK: - Price Per Hour

    private var pricePerHourField: some View {
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

            let cents = Int(pricePerHourCents) ?? 20
            let ex15 = max(1, Int(round(Double(15) / 60.0 * Double(cents))))
            Text("e.g. a 15-min break costs \(ex15)¢ (\(String(format: "$%.2f", Double(ex15) / 100.0)))")
                .font(TuffFonts.caption(11))
                .foregroundColor(TuffColors.textSecondary)
        }
    }

    // MARK: - Invite Code

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("INVITE CODE")
            HStack {
                Image(systemName: "link")
                    .foregroundColor(TuffColors.textSecondary)
                TextField("Auto-generated on create", text: $inviteCode)
                    .font(TuffFonts.body(13))
                    .autocapitalization(.allCharacters)
                    .autocorrectionDisabled()
                Button {
                    inviteCode = String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })
                } label: {
                    Text("Generate")
                        .font(TuffFonts.tag())
                        .foregroundColor(TuffColors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TuffColors.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(12)
            .background(TuffColors.tagBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Share this code with friends to invite them")
                .font(TuffFonts.caption(11))
                .foregroundColor(TuffColors.textSecondary)
        }
    }

    // MARK: - Create Button

    private var createButton: some View {
        Button {
            Task { await createLeague() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(leagueName.trimmingCharacters(in: .whitespaces).isEmpty ? Color(hex: "E0E0E0") : TuffColors.accent)
                    .frame(height: 54)
                if isCreating {
                    ProgressView().tint(.black)
                } else {
                    Text("+ CREATE LEAGUE")
                        .font(TuffFonts.newButton())
                        .foregroundColor(.black)
                        .tracking(0.09 * 17)
                }
            }
        }
        .disabled(leagueName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
        .padding(.top, 6)
    }

    // MARK: - Firestore save

    private func createLeague() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isCreating = true
        errorMessage = nil

        let db = Firestore.firestore()

        // Ensure invite code is unique, auto-retry up to 5 times
        var finalCode = inviteCode.isEmpty
            ? String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })
            : inviteCode.uppercased()
        for _ in 0..<5 {
            let snap = try? await db.collection("leagues")
                .whereField("inviteCode", isEqualTo: finalCode)
                .limit(to: 1)
                .getDocuments()
            if snap?.documents.isEmpty == true { break }
            finalCode = String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })
        }
        let code = finalCode

        let userDoc = try? await db.collection("users").document(uid).getDocument()
        let userData = userDoc?.data()
        let firstName = userData?["firstName"] as? String ?? ""
        let lastName  = userData?["lastName"]  as? String ?? ""
        let username  = userData?["username"]  as? String ?? ""
        let memberProfile: [String: Any] = [
            "uid": uid,
            "name": "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces),
            "username": username,
            "screenTimeMinutes": 0
        ]

        let docRef = db.collection("leagues").document()
        do {
            try await docRef.setData([
                "name": leagueName.trimmingCharacters(in: .whitespaces),
                "createdBy": uid,
                "startDate": Timestamp(date: startDate),
                "endDate": Timestamp(date: endDate),
                "pricePerHourCents": Int(pricePerHourCents) ?? 20,
                "inviteCode": code,
                "memberUids": [uid],
                "memberProfiles": [memberProfile],
                "isActive": true,
                "createdAt": FieldValue.serverTimestamp()
            ])

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(TuffFonts.sectionHeader())
            .foregroundColor(TuffColors.textSecondary)
            .tracking(0.15 * 12)
    }
}

// MARK: - Join League Sheet

struct JoinLeagueView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Enter the invite code shared by the league creator.")
                    .font(.system(size: 15))
                    .foregroundColor(TuffColors.textSecondary)

                TextField("INVITE CODE", text: $code)
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                    .autocapitalization(.allCharacters)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(Color(hex: "F5F5F5"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }

                Button {
                    Task {
                        isJoining = true
                        errorMessage = nil
                        if let err = await viewModel.joinLeague(inviteCode: code) {
                            errorMessage = err
                        } else {
                            dismiss()
                        }
                        isJoining = false
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(code.isEmpty ? Color(hex: "E0E0E0") : TuffColors.accent)
                            .frame(height: 54)
                        if isJoining {
                            ProgressView().tint(.black)
                        } else {
                            Text("JOIN LEAGUE")
                                .font(TuffFonts.newButton())
                                .foregroundColor(.black)
                        }
                    }
                }
                .disabled(code.isEmpty || isJoining)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Join a League")
            .navigationBarTitleDisplayMode(.inline)
            .colorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(TuffColors.textSecondary)
                }
            }
        }
    }
}
