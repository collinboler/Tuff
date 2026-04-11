import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CreateLeagueView: View {
    @Environment(\.dismiss) private var dismiss

    private enum LeagueDuration: String, CaseIterable {
        case week = "WEEK"
        case month = "MONTH"

        var endDate: Date {
            switch self {
            case .week:
                return Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            case .month:
                return Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
            }
        }
    }

    @State private var leagueName = ""
    @State private var selectedDuration: LeagueDuration = .week
    @State private var pricePerHourCents = "20"
    @State private var inviteCode = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    nameField
                    durationRow
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
            TextField("e.g. E Club", text: $leagueName)
                .font(TuffFonts.body(14))
                .padding(12)
                .background(TuffColors.tagBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Duration

    private var durationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DURATION")
            HStack(spacing: 10) {
                ForEach(LeagueDuration.allCases, id: \.self) { duration in
                    let isSelected = selectedDuration == duration
                    Button {
                        selectedDuration = duration
                    } label: {
                        Text(duration.rawValue)
                            .font(TuffFonts.newButton())
                            .foregroundColor(isSelected ? .white : TuffColors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isSelected ? TuffColors.accent : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(TuffColors.accent.opacity(isSelected ? 0 : 0.55), lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                }
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
                    inviteCode = generateInviteCode()
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
                    ProgressView().tint(.white)
                } else {
                    Text("+ CREATE LEAGUE")
                        .font(TuffFonts.newButton())
                        .foregroundColor(.white)
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
        let startDate = Date()
        let endDate = selectedDuration.endDate

        // Ensure invite code is unique, auto-retry up to 5 times
        var finalCode = inviteCode.isEmpty
            ? generateInviteCode()
            : inviteCode.uppercased()
        for _ in 0..<5 {
            let snap = try? await db.collection("leagues")
                .whereField("inviteCode", isEqualTo: finalCode)
                .limit(to: 1)
                .getDocuments()
            if snap?.documents.isEmpty == true { break }
            finalCode = generateInviteCode()
        }
        let code = finalCode

        let userDoc = try? await db.collection("users").document(uid).getDocument()
        let userData = userDoc?.data()
        let firstName = userData?["firstName"] as? String ?? ""
        let lastName  = userData?["lastName"]  as? String ?? ""
        let username  = userData?["username"]  as? String ?? ""
        var memberProfile: [String: Any] = [
            "uid": uid,
            "name": "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces),
            "username": username,
            "screenTimeMinutes": 0,
            "joinedAt": Timestamp(date: Date())
        ]
        if let photoURL = userData?["photoURL"] as? String {
            memberProfile["photoURL"] = photoURL
        }

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

    private func generateInviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        guard !alphabet.isEmpty else {
            return String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6))
        }
        return String((0..<6).compactMap { _ in alphabet.randomElement() })
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
                            ProgressView().tint(.white)
                        } else {
                            Text("JOIN LEAGUE")
                                .font(TuffFonts.newButton())
                                .foregroundColor(.white)
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
