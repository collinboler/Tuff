import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct FeedView: View {
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @State private var showSearch = false
    @State private var showNotifications = false
    @State private var posts: [DailyRecord] = []
    @State private var currentUserName = ""
    @State private var currentUserImage: UIImage? = nil

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    if posts.isEmpty {
                        emptyState
                    } else {
                        ForEach(posts) { record in
                            FeedPostCard(
                                record: record,
                                userName: currentUserName,
                                profileImage: currentUserImage
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 18) {
                        Button { showSearch = true } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.black)
                        }
                        Button { showNotifications = true } label: {
                            Image(systemName: "bell")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.black)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            UserSearchView()
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView()
        }
        .onAppear(perform: loadData)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 52))
                .foregroundColor(Color(hex: "E0E0E0"))
            Text("No posts yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.black)
            Text("Your daily screen time will appear here\neach morning after the first full day.")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func loadData() {
        // Load daily posts from shared store
        let history = TuffSharedStore.dailyHistory()
            .filter { !Calendar.current.isDateInToday($0.date) } // exclude today (that's live)
            .sorted { $0.date > $1.date }
        // Include today if we have data
        if let todaySeconds = TuffSharedStore.todayScreenTime() {
            let today = DailyRecord(id: UUID(), date: Calendar.current.startOfDay(for: Date()),
                                    totalSeconds: todaySeconds, appBreakdown: [])
            posts = [today] + history
        } else {
            posts = history
        }

        // Load user info
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            let doc = try? await Firestore.firestore().collection("users").document(uid).getDocument()
            if let data = doc?.data() {
                let first = data["firstName"] as? String ?? ""
                let last  = data["lastName"]  as? String ?? ""
                await MainActor.run {
                    currentUserName = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
                }
            }
            // Load profile image
            let url = AuthViewModel.profileImageURL(for: uid)
            if let data = try? Data(contentsOf: url),
               let img  = UIImage(data: data) {
                await MainActor.run { currentUserImage = img }
            }
        }
    }
}

// MARK: - Feed Post Card

struct FeedPostCard: View {
    let record: DailyRecord
    let userName: String
    let profileImage: UIImage?

    private let goalSeconds: TimeInterval = 10800 // 3h goal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // User header
            HStack(spacing: 10) {
                ProfileImageView(
                    imageName: "",
                    size: 38,
                    borderColor: TuffColors.accent,
                    borderWidth: 2,
                    uiImage: profileImage
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(userName.isEmpty ? "YOU" : userName.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .tracking(0.5)
                    Text(dateLabel)
                        .font(.system(size: 11))
                        .foregroundColor(TuffColors.textSecondary)
                }
                Spacer()
                // Badge: under/over goal
                Text(record.totalSeconds < goalSeconds ? "UNDER GOAL" : "OVER GOAL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(record.totalSeconds < goalSeconds ? TuffColors.accent : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (record.totalSeconds < goalSeconds ? TuffColors.accent : Color.red).opacity(0.1)
                    )
                    .clipShape(Capsule())
            }

            // Big screen time
            Text(record.formattedTime)
                .font(.system(size: 42, weight: .black, design: .default).width(.condensed))
                .foregroundColor(.black)
                .tracking(-0.5)

            // Progress bar vs goal
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    let fraction = min(record.totalSeconds / goalSeconds, 1.0)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: "F0F0F0"))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(fraction < 1 ? TuffColors.accent : Color.red)
                            .frame(width: geo.size.width * CGFloat(fraction), height: 5)
                    }
                }
                .frame(height: 5)

                HStack {
                    Text("0h")
                        .font(.system(size: 10))
                        .foregroundColor(TuffColors.textSecondary)
                    Spacer()
                    Text("Goal: 3h")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TuffColors.textSecondary)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "EFEFEF"), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var dateLabel: String {
        if Calendar.current.isDateInToday(record.date) { return "Today • Posted automatically" }
        if Calendar.current.isDateInYesterday(record.date) { return "Yesterday • Posted automatically" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: record.date) + " • Posted automatically"
    }
}

// MARK: - Notifications View

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var requests: [FriendRequest] = []
    @State private var isLoading = true

    struct FriendRequest: Identifiable {
        let id: String
        let fromUid: String
        let fromName: String
        let fromUsername: String
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if requests.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "bell.slash")
                            .font(.system(size: 52))
                            .foregroundColor(Color(hex: "E0E0E0"))
                        Text("No notifications")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                        Text("Friend requests will appear here.")
                            .font(.system(size: 14))
                            .foregroundColor(TuffColors.textSecondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                } else {
                    List(requests) { req in
                        HStack(spacing: 12) {
                            ProfileImageView(imageName: "", size: 40,
                                            borderColor: TuffColors.accent, borderWidth: 1.5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(req.fromName.uppercased())
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                                    .tracking(0.3)
                                if !req.fromUsername.isEmpty {
                                    Text("@\(req.fromUsername)")
                                        .font(.system(size: 12))
                                        .foregroundColor(TuffColors.textSecondary)
                                }
                                Text("Sent you a friend request")
                                    .font(.system(size: 11))
                                    .foregroundColor(TuffColors.textSecondary)
                            }
                            Spacer()
                            Button { acceptRequest(req) } label: {
                                Text("Accept")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(TuffColors.accent)
                                    .clipShape(Capsule())
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.white)
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                    .background(Color.white)
                }
            }
            .background(Color.white)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .colorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(TuffColors.accent)
                }
            }
        }
        .onAppear { loadRequests() }
    }

    private func loadRequests() {
        guard let myUid = Auth.auth().currentUser?.uid else { isLoading = false; return }
        Task {
            let db = Firestore.firestore()
            let snap = try? await db.collection("friendRequests")
                .whereField("toUid", isEqualTo: myUid)
                .whereField("status", isEqualTo: "pending")
                .getDocuments()
            let reqs: [FriendRequest] = snap?.documents.compactMap { doc in
                let d = doc.data()
                guard let fromUid = d["fromUid"] as? String else { return nil }
                return FriendRequest(
                    id: doc.documentID,
                    fromUid: fromUid,
                    fromName: d["fromName"] as? String ?? "Unknown",
                    fromUsername: d["fromUsername"] as? String ?? ""
                )
            } ?? []
            await MainActor.run {
                requests = reqs
                isLoading = false
            }
        }
    }

    private func acceptRequest(_ req: FriendRequest) {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        requests.removeAll { $0.id == req.id }
        Task {
            let db = Firestore.firestore()
            try? await db.collection("friendRequests").document(req.id)
                .updateData(["status": "accepted"])
            try? await db.collection("users").document(myUid)
                .collection("friends").document(req.fromUid).setData(["uid": req.fromUid])
            try? await db.collection("users").document(req.fromUid)
                .collection("friends").document(myUid).setData(["uid": myUid])
        }
    }
}
