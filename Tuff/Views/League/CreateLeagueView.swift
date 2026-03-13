import SwiftUI
import FamilyControls

struct CreateLeagueView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var leagueName = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()
    @State private var costPerPerson = "5"
    @State private var inviteCode = ""
    @State private var showAppPicker = false
    @State private var selectedApps = FamilyActivitySelection()
    @State private var blockingMode: BlockingMode = .none

    @EnvironmentObject var screenTimeManager: ScreenTimeManager

    enum BlockingMode: String, CaseIterable {
        case none = "None"
        case friend2FA = "Friend 2FA"
        case customChallenge = "Custom Challenge"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    nameField
                    datesRow
                    buyInField
                    appBlocking
                    inviteField
                    createButton
                }
                .padding(20)
            }
            .background(Color.white)
            .navigationTitle("New League")
            .navigationBarTitleDisplayMode(.large)
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

    // MARK: - Buy-in

    private var buyInField: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("BUY-IN PER PERSON")
            HStack {
                Text("$")
                    .font(TuffFonts.leagueCardPot())
                    .foregroundColor(.black)
                TextField("0", text: $costPerPerson)
                    .font(TuffFonts.leagueCardPot())
                    .keyboardType(.numberPad)
            }
            .padding(12)
            .background(TuffColors.tagBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Set to $0 for a free league")
                .font(TuffFonts.caption(11))
                .foregroundColor(TuffColors.textSecondary)
        }
    }

    // MARK: - App Blocking

    private var appBlocking: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("APP BLOCKING (OPTIONAL)")

            Button {
                showAppPicker = true
            } label: {
                HStack {
                    Image(systemName: "apps.iphone")
                        .font(.system(size: 16))
                    Text("Choose Apps to Block")
                        .font(TuffFonts.body(14))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                }
                .foregroundColor(.black)
                .padding(12)
                .background(TuffColors.tagBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .familyActivityPicker(isPresented: $showAppPicker, selection: $selectedApps)

            ForEach(BlockingMode.allCases.filter { $0 != .none }, id: \.rawValue) { mode in
                blockingOption(mode: mode)
            }
        }
    }

    private func blockingOption(mode: BlockingMode) -> some View {
        Button {
            blockingMode = mode
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode == .friend2FA ? "person.2.fill" : "sparkles")
                    .font(.system(size: 14))
                    .foregroundColor(TuffColors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.rawValue)
                        .font(TuffFonts.body(13))
                        .foregroundColor(.black)
                    Text(mode == .friend2FA
                         ? "A friend must send you a code to unblock"
                         : "Complete a task to earn screen time")
                        .font(TuffFonts.caption(10))
                        .foregroundColor(TuffColors.textSecondary)
                }

                Spacer()

                Image(systemName: blockingMode == mode ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(blockingMode == mode ? TuffColors.accent : TuffColors.navInactive)
            }
            .padding(10)
            .background(blockingMode == mode ? TuffColors.accent.opacity(0.08) : TuffColors.tagBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(blockingMode == mode ? TuffColors.accent.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
    }

    // MARK: - Invite

    private var inviteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("INVITE FRIENDS")
            HStack {
                Image(systemName: "link")
                    .foregroundColor(TuffColors.textSecondary)
                TextField("Tap Generate for an invite code", text: $inviteCode)
                    .font(TuffFonts.body(13))
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
        }
    }

    // MARK: - Create Button

    private var createButton: some View {
        Button {
            screenTimeManager.selectedAppsToBlock = selectedApps
            screenTimeManager.blockSelectedApps()
            dismiss()
        } label: {
            Text("+ CREATE LEAGUE")
                .font(TuffFonts.newButton())
                .foregroundColor(.black)
                .tracking(0.09 * 17)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TuffColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 6)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(TuffFonts.sectionHeader())
            .foregroundColor(TuffColors.textSecondary)
            .tracking(0.15 * 12)
    }
}
