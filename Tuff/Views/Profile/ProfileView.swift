import SwiftUI
import PhotosUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showEdit = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                topBar
                profileHero
                statsRow
                leagueHistory
            }
            .padding(.bottom, 16)
        }
        .background(Color.white)
        .sheet(isPresented: $showEdit) {
            EditProfileView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text("PROFILE")
                .font(TuffFonts.pageTitle())
                .foregroundColor(.black)
                .tracking(0.06 * 26)
            Spacer()
            Button("Edit") { showEdit = true }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(TuffColors.accent)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Profile Hero

    private var profileHero: some View {
        VStack(spacing: 6) {
            ProfileImageView(
                imageName: viewModel.user.imageName,
                size: 82,
                borderColor: TuffColors.accent,
                borderWidth: 3,
                uiImage: viewModel.profileImage
            )

            Text(viewModel.user.name.uppercased())
                .font(TuffFonts.profileName())
                .foregroundColor(.black)
                .tracking(0.05 * 26)
                .padding(.top, 4)

            if !viewModel.user.username.isEmpty {
                Text("@\(viewModel.user.username)")
                    .font(TuffFonts.caption(13))
                    .foregroundColor(TuffColors.textSecondary)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 20)
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
        .padding(.vertical, 16)
        .background(TuffColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - League History

    private var leagueHistory: some View {
        Group {
            if !viewModel.leagueHistory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LEAGUE HISTORY")
                        .font(TuffFonts.sectionHeader())
                        .foregroundColor(TuffColors.textSecondary)
                        .tracking(0.15 * 12)
                        .padding(.horizontal, 22)
                        .padding(.top, 20)

                    VStack(spacing: 6) {
                        ForEach(viewModel.leagueHistory) { entry in
                            LeagueHistoryRow(entry: entry)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

#Preview {
    ProfileView()
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
                                borderColor: TuffColors.accent,
                                borderWidth: 2.5,
                                uiImage: newImage ?? viewModel.profileImage
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
