import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirm = false
    @State private var showDeleteAccount = false

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
                    HStack(spacing: 12) {
                        Image(systemName: screenTimeManager.isAuthorized ? "lock.fill" : "lock.slash")
                            .font(.system(size: 16))
                            .frame(width: 28)
                            .foregroundColor(TuffColors.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screen Time")
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                            Text(screenTimeManager.isAuthorized ? "Authorized — blocking active" : "Not authorized")
                                .font(.system(size: 12))
                                .foregroundColor(TuffColors.textSecondary)
                        }
                    }
                } header: {
                    Text("Status")
                }
                .listRowBackground(Color.white)

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

                Section {
                    Button(role: .destructive) {
                        showDeleteAccount = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash")
                                .font(.system(size: 16))
                                .frame(width: 28)
                            Text("Delete Account")
                                .font(.system(size: 16))
                        }
                        .foregroundColor(.red)
                    }
                } footer: {
                    Text("Permanently deletes your profile, leagues, posts, and all associated data. This can't be undone.")
                        .font(.system(size: 12))
                        .foregroundColor(TuffColors.textSecondary)
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
        .sheet(isPresented: $showDeleteAccount) {
            DeleteAccountView()
                .environmentObject(auth)
        }
    }
}

// MARK: - Delete Account Flow

private struct DeleteAccountView: View {
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Stage { case confirm, code, working, done }
    @State private var stage: Stage = .confirm
    @State private var verificationID: String? = nil
    @State private var code: String = ""
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                switch stage {
                case .confirm: confirmStage
                case .code:    codeStage
                case .working: workingStage
                case .done:    doneStage
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .colorScheme(.light)
            .toolbar {
                if stage != .working && stage != .done {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(TuffColors.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: Stages

    private var confirmStage: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 12)

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundColor(.red)

            Text("This is permanent")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)

            VStack(alignment: .leading, spacing: 10) {
                bullet("Your profile, username, and photo will be erased.")
                bullet("You'll be removed from every league you're in.")
                bullet("Your posts and friend connections will be deleted.")
                bullet("You'll need to verify your phone number to continue.")
            }
            .padding(.horizontal, 28)

            Spacer()

            if let err = errorMessage {
                Text(err).font(.system(size: 13)).foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button {
                Task { await startDelete() }
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private var codeStage: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 12)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(TuffColors.accent)

            Text("Verify it's you")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)

            Text("Enter the 6-digit code we just texted to your phone.")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 28, weight: .bold, design: .monospaced).monospacedDigit())
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .background(Color(hex: "F5F5F5"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 28)

            if let err = errorMessage {
                Text(err).font(.system(size: 13)).foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer()

            Button {
                Task { await finishDelete() }
            } label: {
                Text("Delete Account")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(code.count >= 6 ? Color.red : Color.red.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(code.count < 6)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private var workingStage: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .tint(TuffColors.accent)
            Text("Deleting your account…")
                .font(.system(size: 15))
                .foregroundColor(TuffColors.textSecondary)
            Spacer()
        }
    }

    private var doneStage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(TuffColors.accent)
            Text("Account deleted")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.black)
            Text("Signing you out now.")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
            Spacer()
        }
        .onAppear {
            // Give the user a second to read the confirmation; dismissing
            // the sheet while the auth listener is already flipping the
            // root view back to phone sign-in is a clean handoff.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                dismiss()
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.red)
                .padding(.top, 3)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Actions

    private func startDelete() async {
        errorMessage = nil
        do {
            let vid = try await auth.sendReauthCode()
            await MainActor.run {
                self.verificationID = vid
                self.stage = .code
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func finishDelete() async {
        guard let vid = verificationID else { return }
        errorMessage = nil
        await MainActor.run { self.stage = .working }
        do {
            try await auth.deleteAccount(reauthVerificationID: vid, code: code)
            await MainActor.run { self.stage = .done }
        } catch {
            await MainActor.run {
                self.stage = .code
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
