import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Final-results screen shown when a league's end date has passed.
///
/// Winner-takes-all:
///   * Winner = lowest-spent non-DQ member (ties broken by earliest-joined).
///   * Every other member owes their `boughtCents` to the winner.
///
/// The current user sees a personalized "You won" / "You owe" summary plus the
/// full breakdown of who pays whom — and a Pay Out / Mark Settled button that
/// archives the league (see HomeViewModel.archivedLeagues).
struct LeagueEndedView: View {
    let league: League
    var onDismiss: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var showPayoutConfirm = false
    @State private var isSettling = false
    @State private var settleError: String?

    private var currentUID: String { Auth.auth().currentUser?.uid ?? "" }
    private var currentMember: LeagueMember? {
        league.members.first { $0.user.uid == currentUID }
    }
    private var userWon: Bool { league.winner?.user.uid == currentUID }
    private var netCents: Int { league.netOutcomeCents(forUid: currentUID) }
    private var alreadySettled: Bool { league.isPaidOut(uid: currentUID) }
    private var owesAmount: Bool { netCents < 0 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    headerSection
                    winnerSpotlight
                    personalOutcomeCard
                    finalStandingsSection
                    if !league.finalPayments.isEmpty {
                        paymentsSection
                    }
                }
                .padding(20)
            }

            VStack(spacing: 10) {
                if let err = settleError {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 4)
                }

                if !alreadySettled {
                    payoutButton
                }
                doneButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 6)
        }
        .background(Color.white)
        .sheet(isPresented: $showPayoutConfirm) {
            PayoutConfirmationSheet(
                league: league,
                currentUID: currentUID,
                userWon: userWon,
                netCents: netCents,
                isSettling: $isSettling
            ) { _ in
                Task {
                    await settle()
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LEAGUE ENDED")
                    .font(TuffFonts.sectionHeader())
                    .foregroundColor(TuffColors.textSecondary)
                    .tracking(0.18 * 12)
                Spacer()
                Button {
                    onDismiss()
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
            }
        }
    }

    // MARK: - Winner Spotlight

    @ViewBuilder
    private var winnerSpotlight: some View {
        if let winner = league.winner {
            HStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    ProfileImageView(
                        imageName: winner.user.imageName,
                        size: 62,
                        photoURL: winner.user.photoURL
                    )
                    .overlay(
                        Circle().stroke(TuffColors.gold, lineWidth: 3)
                    )
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14))
                        .foregroundColor(TuffColors.goldBright)
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.85)))
                        .offset(x: 4, y: -4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("WINNER")
                        .font(TuffFonts.sectionHeader())
                        .foregroundColor(TuffColors.gold)
                        .tracking(0.2 * 12)

                    Text(winner.user.name.uppercased())
                        .font(TuffFonts.panelName())
                        .foregroundColor(.black)
                        .tracking(0.04 * 18)
                        .lineLimit(1)

                    Text("Spent \(winner.formattedBoughtCost) · Takes \(String(format: "$%.2f", league.poolDollars))")
                        .font(TuffFonts.caption(12))
                        .foregroundColor(TuffColors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(TuffColors.payoutBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(TuffColors.gold.opacity(0.35), lineWidth: 1)
            )
        } else {
            Text("No eligible winner — every member was disqualified.")
                .font(TuffFonts.body(13))
                .foregroundColor(TuffColors.textSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TuffColors.payoutBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Personal Outcome

    @ViewBuilder
    private var personalOutcomeCard: some View {
        let absDollars = String(format: "$%.2f", Double(abs(netCents)) / 100.0)

        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR RESULT")
                .font(TuffFonts.sectionHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.2 * 12)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(outcomeHeadline)
                    .font(TuffFonts.panelName())
                    .foregroundColor(.black)
                    .tracking(0.04 * 18)
                Spacer()
                Text(signedAmount(absDollars))
                    .font(TuffFonts.historyPayout())
                    .foregroundColor(outcomeTint)
                    .monospacedDigit()
            }

            Text(outcomeSubtitle)
                .font(TuffFonts.caption(12))
                .foregroundColor(TuffColors.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(outcomeTint.opacity(0.08))
        )
    }

    private var outcomeHeadline: String {
        if currentMember == nil { return "NOT A MEMBER" }
        if userWon { return "YOU WON!" }
        if netCents == 0 { return "YOU BROKE EVEN" }
        if currentMember?.isDQ == true { return "YOU WERE DQ'D" }
        return "YOU OWE"
    }

    private var outcomeSubtitle: String {
        guard let me = currentMember else {
            return "You weren't a member of this league."
        }
        if userWon {
            return "Lowest spent takes the pool. Collect from each member below."
        }
        if me.isDQ {
            return "You left mid-season so you're ineligible to win, but your spend still contributes to the pool."
        }
        if netCents == 0 {
            return "You didn't spend anything on breaks — nothing to pay."
        }
        if let winnerName = league.winner?.user.name, !winnerName.isEmpty {
            return "Pay \(winnerName) the amount above to settle your spend."
        }
        return "Pay the amount above to settle your spend."
    }

    private func signedAmount(_ text: String) -> String {
        if userWon { return "+\(text)" }
        if netCents == 0 { return text }
        return "-\(text)"
    }

    private var outcomeTint: Color {
        if userWon { return TuffColors.accent }
        if netCents == 0 { return TuffColors.textSecondary }
        return TuffColors.negative
    }

    // MARK: - Final Standings

    private var finalStandingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FINAL STANDINGS")
                .font(TuffFonts.sectionHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.2 * 12)

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
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(TuffColors.payoutBg)
            )
        }
    }

    // MARK: - Payments

    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHO PAYS WHOM")
                .font(TuffFonts.sectionHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.2 * 12)

            VStack(spacing: 6) {
                ForEach(league.finalPayments) { payment in
                    paymentRow(payment)
                }
            }

            Text("Winner collects each loser's spend. Settle amounts however your league usually pays.")
                .font(TuffFonts.caption(11))
                .foregroundColor(TuffColors.textSecondary)
        }
    }

    private func paymentRow(_ payment: LeaguePayment) -> some View {
        let isYouPaying = payment.from.user.uid == currentUID
        let isYouReceiving = payment.to.user.uid == currentUID

        return HStack(spacing: 12) {
            ProfileImageView(
                imageName: payment.from.user.imageName,
                size: 34,
                photoURL: payment.from.user.photoURL
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(isYouPaying
                     ? "YOU → \(payment.to.user.name.uppercased())"
                     : "\(payment.from.user.name.uppercased()) → \(isYouReceiving ? "YOU" : payment.to.user.name.uppercased())")
                    .font(TuffFonts.lbName())
                    .foregroundColor(.black)
                    .tracking(0.03 * 15)
                    .lineLimit(1)

                Text(payment.from.isDQ ? "DQ'd — still contributes to pool" : "Spent \(payment.from.formattedBoughtCost)")
                    .font(TuffFonts.caption(11))
                    .foregroundColor(TuffColors.textSecondary)
            }

            Spacer()

            Text(payment.amountText)
                .font(TuffFonts.historyPayout())
                .foregroundColor(
                    isYouReceiving ? TuffColors.accent :
                    (isYouPaying ? TuffColors.negative : .black)
                )
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isYouPaying ? TuffColors.negative.opacity(0.06) :
                    isYouReceiving ? TuffColors.accent.opacity(0.08) :
                    TuffColors.payoutBg
                )
        )
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button {
            onDismiss()
            dismiss()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(TuffColors.accent)
                    .frame(height: 52)
                Text("DONE")
                    .font(TuffFonts.newButton())
                    .foregroundColor(.white)
                    .tracking(0.09 * 17)
            }
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Pay Out Button

    /// Red button shown above the green Done button on ended leagues. Label
    /// changes based on the user's role:
    ///   * Loser  → "PAY OUT" → opens confirmation with winner's payment info
    ///   * Winner → "MARK AS SETTLED" → confirms they've collected
    /// Either path archives the league for the current user.
    private var payoutButton: some View {
        Button {
            showPayoutConfirm = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red)
                    .frame(height: 52)
                if isSettling {
                    ProgressView().tint(.white)
                } else {
                    Text(payoutButtonTitle)
                        .font(TuffFonts.newButton())
                        .foregroundColor(.white)
                        .tracking(0.09 * 17)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isSettling)
    }

    private var payoutButtonTitle: String {
        if currentMember == nil { return "ARCHIVE" }
        if userWon { return "MARK AS SETTLED" }
        if !owesAmount { return "ARCHIVE" }
        return "PAY OUT"
    }

    // MARK: - Settle action

    /// Marks the league as paid out for the current user and (when they owe
    /// the winner) writes a notification doc into the winner's
    /// `users/{winnerUid}/notifications` subcollection. The winner's app
    /// listens for new entries and surfaces a local notification reading
    /// "Congratulations! [Name] has paid you $X for [League name]".
    private func settle() async {
        guard !currentUID.isEmpty else { return }
        isSettling = true
        settleError = nil
        defer { isSettling = false }

        let db = Firestore.firestore()
        let leagueRef = db.collection("leagues").document(league.id)

        do {
            try await leagueRef.updateData([
                "paidOutUids": FieldValue.arrayUnion([currentUID])
            ])
        } catch {
            settleError = error.localizedDescription
            return
        }

        // Notify the winner only when the current user is actually paying.
        if owesAmount, let winner = league.winner, winner.user.uid != currentUID {
            let amountCents = abs(netCents)
            let dollars = String(format: "$%.2f", Double(amountCents) / 100.0)
            let myName = currentMember?.user.name.isEmpty == false
                ? currentMember!.user.name
                : (currentMember?.user.username ?? "Someone")

            let notif: [String: Any] = [
                "title": "You got paid!",
                "body": "Congratulations! \(myName) has paid you \(dollars) for \(league.name)",
                "type": "league_payout",
                "leagueId": league.id,
                "fromUid": currentUID,
                "amountCents": amountCents,
                "delivered": false,
                "createdAt": FieldValue.serverTimestamp()
            ]
            _ = try? await db.collection("users").document(winner.user.uid)
                .collection("notifications").addDocument(data: notif)
        }

        showPayoutConfirm = false
        onDismiss()
        dismiss()
    }
}

// MARK: - Payout Confirmation Sheet

/// Modal shown when the current user taps PAY OUT (loser) or MARK AS SETTLED
/// (winner). Surfaces the winner's payment method + ID so the loser knows how
/// to pay them, with Confirm/Cancel buttons that drive `settle()`.
private struct PayoutConfirmationSheet: View {
    let league: League
    let currentUID: String
    let userWon: Bool
    let netCents: Int
    @Binding var isSettling: Bool
    let onConfirm: (League) -> Void

    @Environment(\.dismiss) private var dismiss

    private var owesAmount: Bool { netCents < 0 }
    private var amountText: String {
        String(format: "$%.2f", Double(abs(netCents)) / 100.0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    summaryCard
                    if let winner = league.winner, owesAmount, !userWon {
                        winnerPaymentCard(winner: winner)
                    }
                    confirmButtons
                }
                .padding(20)
            }
            .background(Color.white)
            .navigationTitle("Confirm Payout")
            .navigationBarTitleDisplayMode(.inline)
            .colorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(TuffColors.textSecondary)
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline)
                .font(TuffFonts.modalTitle())
                .foregroundColor(.black)
                .tracking(0.05 * 22)
                .fixedSize(horizontal: false, vertical: true)

            Text(subheadline)
                .font(TuffFonts.body(14))
                .foregroundColor(TuffColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(TuffColors.payoutBg)
        )
    }

    private var headline: String {
        if userWon { return "MARK \(league.name.uppercased()) AS SETTLED?" }
        if !owesAmount { return "ARCHIVE \(league.name.uppercased())?" }
        guard let winner = league.winner else { return "ARCHIVE LEAGUE?" }
        return "YOU OWE \(winner.user.name.uppercased()) \(amountText)"
    }

    private var subheadline: String {
        if userWon {
            return "Confirming will archive \(league.name) on your home screen. Use this once you've collected from everyone."
        }
        if !owesAmount {
            return "You don't owe anything. Archiving moves \(league.name) to your archive list."
        }
        return "Send \(amountText) to \(league.winner?.user.name ?? "the winner") via the payment info below, then confirm. They'll get a notification once you do."
    }

    private func winnerPaymentCard(winner: LeagueMember) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW TO PAY")
                .font(TuffFonts.payoutHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.14 * 11)

            HStack(spacing: 12) {
                ProfileImageView(
                    imageName: winner.user.imageName,
                    size: 44,
                    photoURL: winner.user.photoURL
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(winner.user.name)
                        .font(TuffFonts.lbName())
                        .foregroundColor(.black)
                        .lineLimit(1)
                    Text(winner.user.paymentDisplay)
                        .font(TuffFonts.caption(13))
                        .foregroundColor(TuffColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if !winner.user.paymentMethod.formattedID(winner.user.paymentID).isEmpty {
                    Button {
                        UIPasteboard.general.string =
                            winner.user.paymentMethod.formattedID(winner.user.paymentID)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(TuffColors.accent)
                            .padding(8)
                            .background(TuffColors.accent.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }

            if winner.user.paymentMethod == .none ||
                winner.user.paymentMethod.formattedID(winner.user.paymentID).isEmpty {
                Text("No payment method on file — reach out via @\(winner.user.username.isEmpty ? winner.user.name : winner.user.username) to settle up.")
                    .font(TuffFonts.caption(11))
                    .foregroundColor(TuffColors.textSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(TuffColors.payoutBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(TuffColors.divider, lineWidth: 1)
        )
    }

    private var confirmButtons: some View {
        VStack(spacing: 10) {
            Button {
                onConfirm(league)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(TuffColors.accent)
                        .frame(height: 52)
                    if isSettling {
                        ProgressView().tint(.white)
                    } else {
                        Text("CONFIRM")
                            .font(TuffFonts.newButton())
                            .foregroundColor(.white)
                            .tracking(0.09 * 17)
                    }
                }
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isSettling)

            Button("Cancel") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(TuffColors.textSecondary)
        }
    }
}
