import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Feed Item (unified model for self + friends)

struct FeedItem: Identifiable {
    let id: String          // "{uid}_{dateString}" — stable dedup key
    let uid: String
    let date: Date
    let totalSeconds: TimeInterval
    let displayName: String
    let profileImage: UIImage?
    let isCurrentUser: Bool
}

// MARK: - FeedView

struct FeedView: View {
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @State private var showSearch = false
    @State private var showNotifications = false
    @State private var feedItems: [FeedItem] = []
    @State private var myName = ""
    @State private var myImage: UIImage? = nil

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    if feedItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(feedItems) { item in
                            FeedPostCard(
                                date: item.date,
                                totalSeconds: item.totalSeconds,
                                userName: item.displayName,
                                profileImage: item.isCurrentUser ? myImage : item.profileImage
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
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
        .sheet(isPresented: $showSearch) { UserSearchView() }
        .sheet(isPresented: $showNotifications) { NotificationsView() }
        .onAppear { Task { await loadAll() } }
    }

    // MARK: - Empty state

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

    // MARK: - Data loading

    private func loadAll() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        // 0. Seed local history if empty (handles users who signed up before seed code existed)
        seedHistoryIfNeeded()

        // 1. Load my profile info
        let userDoc = try? await db.collection("users").document(uid).getDocument()
        let first = userDoc?.data()?["firstName"] as? String ?? ""
        let last  = userDoc?.data()?["lastName"]  as? String ?? ""
        let displayName = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        let imgURL = AuthViewModel.profileImageURL(for: uid)
        let img = (try? Data(contentsOf: imgURL)).flatMap { UIImage(data: $0) }
        await MainActor.run { myName = displayName; myImage = img }

        // 2. Show local posts immediately while Firestore loads
        let localItems = buildLocalItems(uid: uid, displayName: displayName)
        await MainActor.run { feedItems = localItems }

        // 3. Upload any local posts not yet in Firestore
        await uploadLocalPosts(uid: uid, displayName: displayName, db: db)

        // 4. Fetch friends
        let friendsSnap = try? await db.collection("users").document(uid)
            .collection("friends").getDocuments()
        let friendUids = (friendsSnap?.documents.compactMap { $0.data()["uid"] as? String } ?? [])

        // 5. Fetch posts from Firestore for self + friends (last 7 days)
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        var allItems: [FeedItem] = []
        let batches = Array(([uid] + friendUids).prefix(10)) // Firestore "in" limit
        let snap = try? await db.collection("posts")
            .whereField("uid", in: batches)
            .whereField("date", isGreaterThan: Timestamp(date: cutoff))
            .order(by: "date", descending: true)
            .getDocuments()

        allItems = snap?.documents.compactMap { doc -> FeedItem? in
            let d = doc.data()
            guard let postUid    = d["uid"]          as? String,
                  let ts         = d["date"]         as? Timestamp,
                  let seconds    = d["totalSeconds"] as? Double,
                  let name       = d["displayName"]  as? String else { return nil }
            return FeedItem(
                id: doc.documentID,
                uid: postUid,
                date: ts.dateValue(),
                totalSeconds: seconds,
                displayName: name,
                profileImage: nil,
                isCurrentUser: postUid == uid
            )
        } ?? []

        // Fill in any local posts for the current user not yet uploaded
        let uploadedDates = Set(allItems.filter { $0.isCurrentUser }
            .map { Calendar.current.startOfDay(for: $0.date) })
        let localOnly = localItems.filter {
            !uploadedDates.contains(Calendar.current.startOfDay(for: $0.date))
        }
        allItems += localOnly
        allItems.sort { $0.date > $1.date }

        await MainActor.run { feedItems = allItems }
    }

    /// Seed the last 3 days of history if it's completely empty.
    /// This ensures users who existed before the seed code was added still see posts.
    private func seedHistoryIfNeeded() {
        guard TuffSharedStore.dailyHistory().isEmpty else { return }
        let calendar = Calendar.current
        let seeded: [DailyRecord] = (1...3).map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
            let seconds = TimeInterval(Int.random(in: 3600...18000)) // 1h – 5h
            return DailyRecord(id: UUID(), date: date, totalSeconds: seconds, appBreakdown: [])
        }
        TuffSharedStore.saveDailyHistory(seeded)
    }

    /// Build feed items from the local TuffSharedStore (current user only).
    private func buildLocalItems(uid: String, displayName: String) -> [FeedItem] {
        let calendar = Calendar.current
        var items: [FeedItem] = []

        // Past days from history
        let history = TuffSharedStore.dailyHistory()
            .filter { !calendar.isDateInToday($0.date) }
        for record in history {
            let ds = Self.dateFmt.string(from: record.date)
            items.append(FeedItem(
                id: "\(uid)_\(ds)",
                uid: uid,
                date: record.date,
                totalSeconds: record.totalSeconds,
                displayName: displayName,
                profileImage: nil,
                isCurrentUser: true
            ))
        }

        // Today (live)
        if let todaySeconds = TuffSharedStore.todayScreenTime() {
            let today = calendar.startOfDay(for: Date())
            let ds = Self.dateFmt.string(from: today)
            items.insert(FeedItem(
                id: "\(uid)_\(ds)_live",
                uid: uid,
                date: today,
                totalSeconds: todaySeconds,
                displayName: displayName,
                profileImage: nil,
                isCurrentUser: true
            ), at: 0)
        }

        return items.sorted { $0.date > $1.date }
    }

    /// Upload recent local posts to Firestore so friends can see them.
    private func uploadLocalPosts(uid: String, displayName: String, db: Firestore) async {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -7, to: Date())!
        let localHistory = TuffSharedStore.dailyHistory()
            .filter { !calendar.isDateInToday($0.date) && $0.date >= cutoff && $0.totalSeconds > 0 }

        for record in localHistory {
            let ds = Self.dateFmt.string(from: record.date)
            let docRef = db.collection("posts").document("\(uid)_\(ds)")
            let exists = (try? await docRef.getDocument())?.exists ?? false
            guard !exists else { continue }
            try? await docRef.setData([
                "uid":          uid,
                "date":         Timestamp(date: record.date),
                "totalSeconds": record.totalSeconds,
                "displayName":  displayName,
                "dateString":   ds
            ])
        }
    }
}

// MARK: - Feed Post Card

struct FeedPostCard: View {
    let date: Date
    let totalSeconds: TimeInterval
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
                Text(totalSeconds < goalSeconds ? "UNDER GOAL" : "OVER GOAL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(totalSeconds < goalSeconds ? TuffColors.accent : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (totalSeconds < goalSeconds ? TuffColors.accent : Color.red).opacity(0.1)
                    )
                    .clipShape(Capsule())
            }

            // Big screen time
            Text(formattedTime)
                .font(.system(size: 42, weight: .black, design: .default).width(.condensed))
                .foregroundColor(.black)
                .tracking(-0.5)

            // Progress bar vs goal
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    let fraction = min(totalSeconds / goalSeconds, 1.0)
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

    private var formattedTime: String {
        let h = Int(totalSeconds) / 3600
        let m = (Int(totalSeconds) % 3600) / 60
        return "\(h)h \(String(format: "%02d", m))m"
    }

    private var dateLabel: String {
        if Calendar.current.isDateInToday(date) { return "Today • Posted automatically" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday • Posted automatically" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date) + " • Posted automatically"
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
            await MainActor.run { requests = reqs; isLoading = false }
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
