import SwiftUI
import PhotosUI
import DeviceActivity
import FirebaseAuth

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @State private var showEdit = false
    @State private var showSettings = false
    @State private var showFriends = false

    @State private var reportID = UUID()

    private var reportFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let todayEnd = calendar.startOfDay(for: Date()).addingTimeInterval(86400)
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: Date())!)
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: todayEnd))
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Combined header: profile info + icons all top-aligned
            profileHeader

            if !viewModel.leagueHistory.isEmpty {
                leagueHistory
            }

            // Stats section fills the rest
            Group {
                if screenTimeManager.isAuthorized {
                    #if !targetEnvironment(simulator)
                    DeviceActivityReport(
                        DeviceActivityReport.Context("TuffDailyActivity"),
                        filter: reportFilter
                    )
                    .id(reportID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 20)
                    #else
                    statsPlaceholder
                    #endif
                } else {
                    screenTimeGate
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white)
        .sheet(isPresented: $showEdit) {
            EditProfileView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showFriends) {
            FriendsListView()
        }
    }

    // MARK: - Combined Profile Header

    private var profileHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ProfileImageView(
                imageName: viewModel.user.imageName,
                size: 56,
                uiImage: viewModel.profileImage,
                photoURL: viewModel.user.photoURL
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.user.name.uppercased())
                    .font(TuffFonts.profileName())
                    .foregroundColor(.black)
                    .tracking(0.05 * 22)

                if !viewModel.user.username.isEmpty {
                    Text("@\(viewModel.user.username)")
                        .font(TuffFonts.caption(13))
                        .foregroundColor(TuffColors.textSecondary)
                }

                // Friends + Edit in same row
                HStack(spacing: 10) {
                    Button { showFriends = true } label: {
                        Text("\(viewModel.friendsCount) friends")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TuffColors.textSecondary)
                    }

                    Button { showEdit = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Edit")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(TuffColors.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .overlay(Capsule().stroke(TuffColors.accent, lineWidth: 1.5))
                    }
                }
                .padding(.top, 2)
            }

            Spacer()

            HStack(spacing: 16) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 8) {
            profileStatBlock(value: "\(viewModel.user.totalLeagues)", label: "Leagues")
            profileStatBlock(value: "\(viewModel.user.leaguesWon)", label: "Won", isGreen: true)
            profileStatBlock(value: viewModel.totalEarningsFormatted, label: "Earned", isGreen: true)
        }
        .padding(.horizontal, 20)
    }

    private func profileStatBlock(value: String, label: String, isGreen: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(TuffFonts.profileStatValue())
                .foregroundColor(isGreen ? TuffColors.accent : .white)
            Text(label.uppercased())
                .font(TuffFonts.profileStatLabel())
                .foregroundColor(.gray)
                .tracking(0.08 * 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(TuffColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - League History

    private var leagueHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LEAGUE HISTORY")
                .font(TuffFonts.sectionHeader())
                .foregroundColor(TuffColors.textSecondary)
                .tracking(0.15 * 12)
                .padding(.horizontal, 22)
                .padding(.top, 16)

            VStack(spacing: 6) {
                ForEach(viewModel.leagueHistory) { entry in
                    LeagueHistoryRow(entry: entry)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Screen Time Gate

    private var screenTimeGate: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hourglass.circle")
                .font(.system(size: 52))
                .foregroundColor(TuffColors.textSecondary)
            Text("Screen Time Not Granted")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.black)
            Text("Allow Screen Time access so Tuff can show your stats.")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                Task { await screenTimeManager.requestAuthorization() }
            } label: {
                Text("Allow Screen Time")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(TuffColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var statsPlaceholder: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 40)
            Text("Stats available on device")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
        }
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var newImage: UIImage? = nil
    @State private var showSourcePicker = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Photo
                    Button { showSourcePicker = true } label: {
                        ZStack(alignment: .bottomTrailing) {
                            ProfileImageView(
                                imageName: "",
                                size: 90,
                                uiImage: newImage ?? viewModel.profileImage,
                                photoURL: viewModel.user.photoURL
                            )
                            Circle()
                                .fill(TuffColors.accent)
                                .frame(width: 28, height: 28)
                                .overlay(Image(systemName: "camera.fill").font(.system(size: 12)).foregroundColor(.white))
                                .offset(x: 4, y: 4)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)

                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NAME")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(TuffColors.textSecondary)
                            .tracking(1)
                        HStack(spacing: 10) {
                            TextField("First", text: $firstName)
                                .padding(12)
                                .background(Color(hex: "F5F5F5"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            TextField("Last", text: $lastName)
                                .padding(12)
                                .background(Color(hex: "F5F5F5"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // Username
                    VStack(alignment: .leading, spacing: 6) {
                        Text("USERNAME")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(TuffColors.textSecondary)
                            .tracking(1)
                        HStack(spacing: 0) {
                            Text("@")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.black)
                                .padding(.leading, 12)
                            Rectangle()
                                .fill(Color(hex: "E0E0E0"))
                                .frame(width: 1, height: 20)
                                .padding(.horizontal, 8)
                            TextField("username", text: $username)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .padding(.trailing, 12)
                        }
                        .frame(height: 48)
                        .background(Color(hex: "F5F5F5"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if let err = errorMessage {
                        Text(err).font(.system(size: 13)).foregroundColor(.red)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .colorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(TuffColors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            isSaving = true
                            errorMessage = nil
                            if let err = await viewModel.updateProfile(
                                firstName: firstName,
                                lastName: lastName,
                                username: username,
                                image: newImage
                            ) {
                                errorMessage = err
                            } else {
                                dismiss()
                            }
                            isSaving = false
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save").bold() }
                    }
                    .foregroundColor(TuffColors.accent)
                    .disabled(isSaving)
                }
            }
        }
        .onAppear {
            let parts = viewModel.user.name.split(separator: " ", maxSplits: 1)
            firstName = parts.first.map(String.init) ?? ""
            lastName  = parts.dropFirst().first.map(String.init) ?? ""
            username  = viewModel.user.username
        }
        .confirmationDialog("Change Photo", isPresented: $showSourcePicker) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") { showCamera = true }
            }
            Button("Choose from Library") { showLibrary = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, image: $newImage).ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) { Text("Choose Photo") }
                .onChange(of: selectedPhoto) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            newImage = img
                            showLibrary = false
                        }
                    }
                }
                .presentationDetents([.medium])
        }
    }
}
