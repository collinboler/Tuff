import SwiftUI
import PhotosUI
import FirebaseFirestore

struct OnboardingView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var screenTimeManager: ScreenTimeManager
    @EnvironmentObject private var notificationManager: NotificationManager

    @State private var step: Step = .name
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var usernameError: String? = nil
    @State private var isCheckingUsername = false
    @State private var profileImage: UIImage? = nil
    @State private var showSourcePicker = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isRequestingScreenTime = false
    @FocusState private var focusedField: Field?

    private enum Step: Int { case name, username, photo, screenTime, notifications }
    private enum Field { case firstName, lastName, username }

    private var totalSteps: Int { 5 }
    private var progressIndex: Int { step.rawValue }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 16)
                    .padding(.horizontal, 32)

                Spacer()

                switch step {
                case .name:          nameStep
                case .username:      usernameStep
                case .photo:         photoStep
                case .screenTime:    screenTimeStep
                case .notifications: notificationsStep
                }

                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .colorScheme(.light)
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, image: $profileImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Text("Choose Photo")
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        profileImage = img
                        showLibrary = false
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Add Photo", isPresented: $showSourcePicker) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") { showCamera = true }
            }
            Button("Choose from Library") { showLibrary = true }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps) { i in
                Capsule()
                    .fill(i <= progressIndex ? TuffColors.accent : Color(hex: "E0E0E0"))
                    .frame(height: 4)
            }
        }
    }

    // MARK: - Name step

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT'S YOUR NAME?")
                    .font(.system(size: 28, weight: .black, design: .default).width(.condensed))
                    .foregroundColor(.black)
                    .tracking(1)
                Text("We'll show this to your league members.")
                    .font(.system(size: 15))
                    .foregroundColor(TuffColors.textSecondary)
            }

            VStack(spacing: 12) {
                TextField("First name", text: $firstName)
                    .font(.system(size: 17))
                    .focused($focusedField, equals: .firstName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .lastName }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(Color(hex: "F5F5F5"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                TextField("Last name", text: $lastName)
                    .font(.system(size: 17))
                    .focused($focusedField, equals: .lastName)
                    .submitLabel(.done)
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(Color(hex: "F5F5F5"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .onAppear { focusedField = .firstName }

            continueButton(title: "Continue",
                           disabled: firstName.trimmingCharacters(in: .whitespaces).isEmpty) {
                step = .username
            }
        }
    }

    // MARK: - Username step

    private var usernameStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PICK A USERNAME")
                    .font(.system(size: 28, weight: .black, design: .default).width(.condensed))
                    .foregroundColor(.black)
                    .tracking(1)
                Text("Your unique @handle for leagues.")
                    .font(.system(size: 15))
                    .foregroundColor(TuffColors.textSecondary)
            }

            HStack(spacing: 0) {
                Text("@")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.leading, 16)
                Rectangle()
                    .fill(Color(hex: "E0E0E0"))
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 10)
                TextField("username", text: $username)
                    .font(.system(size: 17))
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                    .padding(.trailing, 16)
            }
            .frame(height: 54)
            .background(Color(hex: "F5F5F5"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear { focusedField = .username }

            if let err = usernameError {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(TuffColors.negative)
            }

            continueButton(
                title: isCheckingUsername ? "Checking..." : "Continue",
                disabled: username.trimmingCharacters(in: .whitespaces).isEmpty || isCheckingUsername
            ) {
                Task { await checkAndAdvanceFromUsername() }
            }
        }
    }

    private func checkAndAdvanceFromUsername() async {
        let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return }
        isCheckingUsername = true
        usernameError = nil

        let db = Firestore.firestore()
        let snap = try? await db.collection("users")
            .whereField("username", isEqualTo: trimmed)
            .limit(to: 1)
            .getDocuments()

        isCheckingUsername = false
        if let docs = snap?.documents, !docs.isEmpty {
            usernameError = "@\(trimmed) is already taken"
        } else {
            username = trimmed
            step = .photo
        }
    }

    // MARK: - Photo step

    private var photoStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ADD A PHOTO")
                    .font(.system(size: 28, weight: .black, design: .default).width(.condensed))
                    .foregroundColor(.black)
                    .tracking(1)
                Text("Help your league members recognize you.")
                    .font(.system(size: 15))
                    .foregroundColor(TuffColors.textSecondary)
            }

            HStack {
                Spacer()
                Button { showSourcePicker = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "F0F0F0"))
                            .frame(width: 120, height: 120)

                        if let img = profileImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(TuffColors.textSecondary)
                                Text("Add Photo")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(TuffColors.textSecondary)
                            }
                        }

                        if profileImage != nil {
                            Circle()
                                .fill(TuffColors.accent)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: "pencil")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                )
                                .offset(x: 40, y: 40)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }

            VStack(spacing: 12) {
                continueButton(title: "Continue", disabled: false) {
                    step = .screenTime
                }
                if profileImage == nil {
                    Button("Skip for now") { step = .screenTime }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(TuffColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Screen Time step

    private var screenTimeStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ALLOW SCREEN TIME")
                    .font(.system(size: 28, weight: .black, design: .default).width(.condensed))
                    .foregroundColor(.black)
                    .tracking(1)
                Text("Tuff needs Screen Time access to track your app usage and compete in leagues.")
                    .font(.system(size: 15))
                    .foregroundColor(TuffColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            iconRow(systemName: "lock.fill", color: TuffColors.accent,
                    title: "Block distracting apps", subtitle: "All selected apps locked by default")
            iconRow(systemName: "trophy.fill", color: TuffColors.gold,
                    title: "Compete in leagues", subtitle: "Lowest break time spent wins")
            iconRow(systemName: "timer", color: Color(hex: "5B8CFF"),
                    title: "Buy breaks", subtitle: "Unlock apps temporarily when you need to")

            continueButton(
                title: isRequestingScreenTime ? "Allowing..." : "Allow Screen Time",
                disabled: isRequestingScreenTime
            ) {
                Task {
                    isRequestingScreenTime = true
                    await screenTimeManager.requestAuthorization()
                    isRequestingScreenTime = false
                    if screenTimeManager.isAuthorized {
                        step = .notifications
                    }
                }
            }
        }
    }

    // MARK: - Notifications step

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("STAY IN THE LOOP")
                    .font(.system(size: 28, weight: .black, design: .default).width(.condensed))
                    .foregroundColor(.black)
                    .tracking(1)
                Text("Get notified when leagues start, end, or someone knocks you off the leaderboard.")
                    .font(.system(size: 15))
                    .foregroundColor(TuffColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            iconRow(systemName: "bell.badge.fill", color: TuffColors.accent,
                    title: "League alerts", subtitle: "Start & end reminders")
            iconRow(systemName: "chart.line.uptrend.xyaxis", color: Color(hex: "5B8CFF"),
                    title: "Weekly recap", subtitle: "See how you trended")

            VStack(spacing: 12) {
                continueButton(title: "Allow Notifications", disabled: false) {
                    Task {
                        await notificationManager.requestPermission()
                        notificationManager.registerNotificationCategories()
                    }
                    finish()
                }

                Button("Maybe later") { finish() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(TuffColors.textSecondary)
            }
        }
    }

    // MARK: - Helpers

    private func finish() {
        auth.completeOnboarding(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            username: username,
            profileImage: profileImage
        )
    }

    private func continueButton(title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 12)
                .fill(disabled ? Color(hex: "E0E0E0") : TuffColors.accent)
                .frame(height: 54)
                .overlay(
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(disabled ? TuffColors.textSecondary : .white)
                )
        }
        .disabled(disabled)
    }

    private func iconRow(systemName: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(TuffColors.textSecondary)
            }
        }
    }
}
