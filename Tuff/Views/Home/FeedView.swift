import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Feed Models

struct FeedItem: Identifiable {
    let id: String          // "{uid}_{dateString}" — stable dedup key
    let uid: String
    let date: Date
    let totalSeconds: TimeInterval
    let displayName: String
    let profileImage: UIImage?
    let isCurrentUser: Bool
    let appBreakdown: [AppSummary]
    var kudoUids: [String]
    var commentCount: Int

    struct AppSummary {
        let name: String
        let bundleID: String
        let seconds: TimeInterval
    }
}

// MARK: - FeedView

struct FeedView: View {
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @State private var showSearch = false
    @State private var showNotifications = false
    @State private var feedItems: [FeedItem] = []
    @State private var myUID = ""
    @State private var myName = ""
    @State private var myImage: UIImage? = nil
    @State private var selectedPostID: String? = nil
    @State private var selectedPostOwnerUID: String? = nil

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    if feedItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(feedItems.indices, id: \.self) { i in
                            FeedPostCard(
                                item: feedItems[i],
                                myUID: myUID,
                                myImage: myImage,
                                onKudo: { toggleKudo(at: i) },
                                onComment: {
                                    selectedPostID = feedItems[i].id
                                    selectedPostOwnerUID = feedItems[i].uid
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .background(Color(hex: "F0F0F0"))
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
        .sheet(isPresented: Binding(
            get: { selectedPostID != nil },
            set: { if !$0 { selectedPostID = nil; selectedPostOwnerUID = nil } }
        )) {
            if let pid = selectedPostID, let ownerUID = selectedPostOwnerUID {
                CommentsView(postID: pid, postOwnerUID: ownerUID,
                             myUID: myUID, myDisplayName: myName) { delta in
                    if let idx = feedItems.firstIndex(where: { $0.id == pid }) {
                        feedItems[idx].commentCount += delta
                    }
                }
            }
        }
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

    // MARK: - Kudos

    private func toggleKudo(at index: Int) {
        guard !feedItems[index].isCurrentUser else { return }
        let item = feedItems[index]
        let db = Firestore.firestore()
        let docRef = db.collection("posts").document(item.id)
        if item.kudoUids.contains(myUID) {
            feedItems[index].kudoUids.removeAll { $0 == myUID }
            Task { try? await docRef.updateData(["kudoUids": FieldValue.arrayRemove([myUID])]) }
        } else {
            feedItems[index].kudoUids.append(myUID)
            Task { try? await docRef.updateData(["kudoUids": FieldValue.arrayUnion([myUID])]) }
        }
    }

    // MARK: - Data loading

    private func loadAll() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        myUID = uid
        let db = Firestore.firestore()

        // 1. Load my profile info
        let userDoc = try? await db.collection("users").document(uid).getDocument()
        let first = userDoc?.data()?["firstName"] as? String ?? ""
        let last  = userDoc?.data()?["lastName"]  as? String ?? ""
        let displayName = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        let imgURL = AuthViewModel.profileImageURL(for: uid)
        let img = (try? Data(contentsOf: imgURL)).flatMap { UIImage(data: $0) }
        await MainActor.run { myName = displayName; myImage = img }

        // 2. Upload any local posts not yet in Firestore
        await uploadLocalPosts(uid: uid, displayName: displayName, db: db)

        // 3. Fetch friends
        let friendsSnap = try? await db.collection("users").document(uid)
            .collection("friends").getDocuments()
        let friendUids = friendsSnap?.documents.compactMap { $0.data()["uid"] as? String } ?? []

        // 4. Fetch yesterday's post for self + each friend by direct document ID (no index needed)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayDS = Self.dateFmt.string(from: yesterday)
        let allUIDs = ([uid] + friendUids).prefix(30)

        var allItems: [FeedItem] = []
        print("[Feed] Fetching yesterday (\(yesterdayDS)) for UIDs: \(Array(allUIDs))")
        await withTaskGroup(of: FeedItem?.self) { group in
            for postUID in allUIDs {
                group.addTask {
                    let docID = "\(postUID)_\(yesterdayDS)"
                    do {
                        let doc = try await db.collection("posts").document(docID).getDocument()
                        guard doc.exists, let d = doc.data() else {
                            print("[Feed] No doc for \(docID)")
                            return nil
                        }
                        guard let ts      = d["date"]         as? Timestamp,
                              let seconds = d["totalSeconds"] as? Double,
                              let name    = d["displayName"]  as? String else {
                            print("[Feed] Missing fields in \(docID): \(d.keys.sorted())")
                            return nil
                        }
                        let kudoUids     = d["kudoUids"]     as? [String] ?? []
                        let commentCount = d["commentCount"] as? Int      ?? 0
                        let rawApps      = d["apps"]         as? [[String: Any]] ?? []
                        let apps = rawApps.compactMap { a -> FeedItem.AppSummary? in
                            guard let n = a["name"] as? String, let s = a["seconds"] as? Double else { return nil }
                            return FeedItem.AppSummary(name: n, bundleID: a["bundleID"] as? String ?? "", seconds: s)
                        }
                        print("[Feed] Loaded \(docID) — \(seconds)s, \(apps.count) apps")
                        return FeedItem(
                            id: docID,
                            uid: postUID,
                            date: ts.dateValue(),
                            totalSeconds: seconds,
                            displayName: name,
                            profileImage: nil,
                            isCurrentUser: postUID == uid,
                            appBreakdown: apps,
                            kudoUids: kudoUids,
                            commentCount: commentCount
                        )
                    } catch {
                        print("[Feed] Error fetching \(docID): \(error)")
                        return nil
                    }
                }
            }
            for await item in group {
                if let item { allItems.append(item) }
            }
        }

        // Sort: current user first, then by display name
        allItems.sort {
            if $0.isCurrentUser != $1.isCurrentUser { return $0.isCurrentUser }
            return $0.displayName < $1.displayName
        }

        await MainActor.run { feedItems = allItems }
    }

    /// Upload recent local posts to Firestore so friends can see them.
    private func uploadLocalPosts(uid: String, displayName: String, db: Firestore) async {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -7, to: Date())!
        let localHistory = TuffSharedStore.dailyHistory()
            .filter { !calendar.isDateInToday($0.date) && $0.date >= cutoff && $0.totalSeconds > 0 }
        print("[Feed] Local history count: \(TuffSharedStore.dailyHistory().count), uploadable: \(localHistory.count)")

        for record in localHistory {
            let ds = Self.dateFmt.string(from: record.date)
            let docRef = db.collection("posts").document("\(uid)_\(ds)")
            let appsData: [[String: Any]] = record.appBreakdown.map { a in
                ["name": a.displayName, "bundleID": a.bundleID, "seconds": a.totalSeconds]
            }
            let exists = (try? await docRef.getDocument())?.exists ?? false
            if exists {
                // Always refresh totalSeconds + apps so real data from DeviceActivityReport
                // overwrites any previously seeded/stale data. Kudos and commentCount preserved.
                try? await docRef.updateData([
                    "totalSeconds": record.totalSeconds,
                    "apps":         appsData,
                    "displayName":  displayName
                ])
            } else {
                try? await docRef.setData([
                    "uid":          uid,
                    "date":         Timestamp(date: record.date),
                    "totalSeconds": record.totalSeconds,
                    "displayName":  displayName,
                    "dateString":   ds,
                    "apps":         appsData,
                    "kudoUids":     [String](),
                    "commentCount": 0
                ])
            }
        }
    }
}

// MARK: - Feed Post Card

struct FeedPostCard: View {
    let item: FeedItem
    let myUID: String
    let myImage: UIImage?
    let onKudo: () -> Void
    let onComment: () -> Void

    private let goalSeconds: TimeInterval = 10800 // used only for simple bar fallback
    private var hasKudo: Bool { item.kudoUids.contains(myUID) }
    private var kudoCount: Int { item.kudoUids.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 10) {
                ProfileImageView(
                    imageName: "",
                    size: 38,
                    uiImage: item.isCurrentUser ? myImage : item.profileImage
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName.isEmpty ? "YOU" : item.displayName.uppercased())
                        .font(.system(size: 13, weight: .black, design: .default).width(.condensed))
                        .foregroundColor(.black)
                        .tracking(0.8)
                    Text(dateLabel)
                        .font(.system(size: 10))
                        .foregroundColor(TuffColors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Big screen time number
            Text(formattedTime)
                .font(.system(size: 52, weight: .black, design: .default).width(.condensed))
                .foregroundColor(.black)
                .tracking(-1)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 2)

            // App breakdown or simple bar
            if !item.appBreakdown.isEmpty {
                appBreakdownBar
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            } else {
                simpleProgressBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // Thin divider
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            // Action row
            HStack(spacing: 0) {
                Button(action: onKudo) {
                    HStack(spacing: 6) {
                        Image(systemName: hasKudo ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(hasKudo ? TuffColors.accent : Color.black.opacity(0.3))
                        if kudoCount > 0 {
                            Text("\(kudoCount)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(hasKudo ? TuffColors.accent : Color.black.opacity(0.3))
                        }
                    }
                    .frame(minWidth: 44, minHeight: 36)
                }
                .disabled(item.isCurrentUser)
                .padding(.trailing, 18)

                Button(action: onComment) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.3))
                        if item.commentCount > 0 {
                            Text("\(item.commentCount)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.black.opacity(0.3))
                        }
                    }
                    .frame(minWidth: 44, minHeight: 36)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - App Breakdown Bar

    private var appBreakdownBar: some View {
        let apps = Array(item.appBreakdown.prefix(5))
        let total = apps.reduce(0) { $0 + $1.seconds }
        let barH: CGFloat = 56

        return VStack(alignment: .leading, spacing: 8) {
            // Thick segmented bar with icons inside
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Colored segments flush together, clipped as one pill
                    HStack(spacing: 0) {
                        ForEach(Array(apps.enumerated()), id: \.offset) { idx, app in
                            let frac = CGFloat(app.seconds / max(total, 1))
                            Rectangle()
                                .fill(appColor(bundleID: app.bundleID, fallback: idx))
                                .frame(width: geo.size.width * frac)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // App icons centered inside each segment
                    ForEach(Array(apps.enumerated()), id: \.offset) { idx, app in
                        let frac = CGFloat(app.seconds / max(total, 1))
                        let segW = geo.size.width * frac
                        let midX = midFraction(idx: idx, apps: apps, total: total) * geo.size.width
                        if segW > 30 {
                            AppSegmentIcon(bundleID: app.bundleID, name: app.name,
                                           size: min(segW - 14, 36))
                                .position(x: midX, y: barH / 2)
                        }
                    }
                }
            }
            .frame(height: barH)

            // Legend
            HStack(spacing: 10) {
                ForEach(Array(apps.prefix(5).enumerated()), id: \.offset) { idx, app in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appColor(bundleID: app.bundleID, fallback: idx))
                            .frame(width: 6, height: 6)
                        Text(app.name)
                            .font(.system(size: 9))
                            .foregroundColor(TuffColors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
    }

    private var simpleProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 7)
                RoundedRectangle(cornerRadius: 4)
                    .fill(TuffColors.accent)
                    .frame(width: geo.size.width, height: 7)
            }
        }
        .frame(height: 7)
    }

    // MARK: - Helpers

    private func midFraction(idx: Int, apps: [FeedItem.AppSummary], total: TimeInterval) -> CGFloat {
        var acc: CGFloat = 0
        for (i, app) in apps.enumerated() {
            let frac = CGFloat(app.seconds / max(total, 1))
            if i == idx { return acc + frac / 2 }
            acc += frac
        }
        return 0.5
    }

    private func appColor(bundleID: String, fallback: Int) -> Color {
        switch bundleID {
        case "com.burbn.instagram":            return Color(hex: "C13584")
        case "com.zhiliaoapp.musically":       return Color(hex: "010101")
        case "com.apple.mobilesafari":         return Color(hex: "006CFF")
        case "com.apple.MobileSMS":            return Color(hex: "34C759")
        case "com.google.ios.youtube":         return Color(hex: "FF0000")
        case "com.atebits.Tweetie2",
             "com.twitter.twitter-iphone":     return Color(hex: "000000")
        case "com.facebook.Facebook":          return Color(hex: "1877F2")
        case "com.toyopagroup.picaboo":        return Color(hex: "FFCD00")
        case "com.reddit.Reddit":              return Color(hex: "FF4500")
        case "com.spotify.client":             return Color(hex: "1DB954")
        case "com.apple.news":                 return Color(hex: "FF3B30")
        case "com.netflix.Netflix":            return Color(hex: "E50914")
        case "com.google.Maps":                return Color(hex: "4285F4")
        case "com.apple.mobilemail":           return Color(hex: "147EFB")
        case "com.apple.mobileslideshow":      return Color(hex: "FF9500")
        case "com.google.chrome.app":          return Color(hex: "4285F4")
        case "com.hammerandchisel.discord":    return Color(hex: "5865F2")
        case "com.linkedin.LinkedIn":          return Color(hex: "0A66C2")
        case "com.pinterest.Pinterest":        return Color(hex: "E60023")
        case "com.bereal.BeReal":              return Color(hex: "1A1A1A")
        default:
            let palette: [Color] = [
                TuffColors.accent, Color(hex: "5B8CFF"), Color(hex: "FF8C42"),
                Color(hex: "C77DFF"), Color(hex: "E53935"),
            ]
            return palette[fallback % palette.count]
        }
    }

    private var formattedTime: String {
        let h = Int(item.totalSeconds) / 3600
        let m = (Int(item.totalSeconds) % 3600) / 60
        return "\(h)h \(String(format: "%02d", m))m"
    }

    private var dateLabel: String {
        if Calendar.current.isDateInToday(item.date) { return "Today · Live" }
        if Calendar.current.isDateInYesterday(item.date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: item.date)
    }
}

// MARK: - App Icon Fetcher

actor AppIconFetcher {
    static let shared = AppIconFetcher()
    private var cache: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {}

    func fetch(bundleID: String) async -> UIImage? {
        if let cached = cache[bundleID] { return cached }
        if let task = inFlight[bundleID] { return await task.value }

        let task = Task<UIImage?, Never> {
            guard !bundleID.isEmpty,
                  let lookupURL = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)"),
                  let (data, _) = try? await URLSession.shared.data(from: lookupURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let artworkString = results.first?["artworkUrl100"] as? String,
                  // Use higher-res 512 version
                  let artworkURL = URL(string: artworkString.replacingOccurrences(of: "100x100", with: "512x512")),
                  let (imgData, _) = try? await URLSession.shared.data(from: artworkURL),
                  let image = UIImage(data: imgData)
            else { return nil }
            return image
        }
        inFlight[bundleID] = task
        let result = await task.value
        inFlight.removeValue(forKey: bundleID)
        if let result { cache[bundleID] = result }
        return result
    }
}

// MARK: - App Segment Icon

struct AppSegmentIcon: View {
    let bundleID: String
    let name: String
    let size: CGFloat

    @State private var icon: UIImage?

    private var initials: String { String(name.prefix(2)).uppercased() }

    var body: some View {
        ZStack {
            if let img = icon {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            } else {
                // Initials fallback while loading
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: size, height: size)
                    Text(initials)
                        .font(.system(size: size * 0.32, weight: .black))
                        .foregroundColor(.white)
                }
            }
        }
        .task(id: bundleID) {
            icon = await AppIconFetcher.shared.fetch(bundleID: bundleID)
        }
    }
}

// MARK: - Comments View

struct CommentsView: View {
    let postID: String
    let postOwnerUID: String
    let myUID: String
    let myDisplayName: String
    var onCountChange: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [PostComment] = []
    @State private var isLoading = true
    @State private var commentText = ""
    @State private var replyTo: PostComment? = nil
    @State private var isSending = false
    @FocusState private var inputFocused: Bool

    struct PostComment: Identifiable {
        let id: String
        let uid: String
        let displayName: String
        let text: String
        let timestamp: Date
        let replyToUID: String?
        let replyToName: String?
        let replyToCommentID: String?
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Comment list
                if isLoading {
                    Spacer()
                    ProgressView().frame(maxWidth: .infinity)
                    Spacer()
                } else if comments.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40))
                            .foregroundColor(Color(hex: "E0E0E0"))
                        Text("No comments yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                        Text("Be the first to comment.")
                            .font(.system(size: 13))
                            .foregroundColor(TuffColors.textSecondary)
                    }
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(comments) { comment in
                                commentRow(comment)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                Divider().padding(.horizontal, 16)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }

                // Reply banner
                if let reply = replyTo {
                    HStack {
                        Text("Replying to @\(reply.displayName)")
                            .font(.system(size: 12))
                            .foregroundColor(TuffColors.accent)
                        Spacer()
                        Button { replyTo = nil } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(TuffColors.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(TuffColors.accent.opacity(0.06))
                }

                // Input bar
                HStack(spacing: 10) {
                    TextField(replyTo != nil ? "Reply…" : "Add a comment…", text: $commentText, axis: .vertical)
                        .font(.system(size: 14))
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(hex: "F5F5F5"))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .onChange(of: commentText) { _, new in
                            // Auto-insert @name on reply start
                            if let reply = replyTo, !new.contains("@\(reply.displayName)") && new.isEmpty {
                                commentText = "@\(reply.displayName) "
                            }
                        }

                    Button {
                        Task { await sendComment() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(commentText.trimmingCharacters(in: .whitespaces).isEmpty
                                             ? Color(hex: "D0D0D0") : TuffColors.accent)
                    }
                    .disabled(commentText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white)
                .overlay(Rectangle().fill(Color(hex: "EFEFEF")).frame(height: 1), alignment: .top)
            }
            .background(Color.white)
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .colorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(TuffColors.accent)
                }
            }
        }
        .onAppear { loadComments() }
    }

    @ViewBuilder
    private func commentRow(_ comment: PostComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Reply context
            if let replyName = comment.replyToName {
                Text("↩ @\(replyName)")
                    .font(.system(size: 11))
                    .foregroundColor(TuffColors.accent)
                    .padding(.bottom, 1)
            }
            HStack(alignment: .top, spacing: 10) {
                ProfileImageView(imageName: "", size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(comment.displayName.isEmpty ? "User" : comment.displayName.uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                            .tracking(0.3)
                        Text(timeAgo(comment.timestamp))
                            .font(.system(size: 11))
                            .foregroundColor(TuffColors.textSecondary)
                        Spacer()
                        // Delete (own comment or post owner)
                        if comment.uid == myUID || postOwnerUID == myUID {
                            Button { deleteComment(comment) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "CCCCCC"))
                            }
                        }
                    }

                    Text(comment.text)
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Reply button
            Button {
                replyTo = comment
                commentText = "@\(comment.displayName) "
                inputFocused = true
            } label: {
                Text("Reply")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TuffColors.textSecondary)
            }
            .padding(.leading, 42)
        }
    }

    private func loadComments() {
        let db = Firestore.firestore()
        db.collection("posts").document(postID).collection("comments")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snap, _ in
                let loaded: [PostComment] = snap?.documents.compactMap { doc in
                    let d = doc.data()
                    guard let uid = d["uid"] as? String,
                          let text = d["text"] as? String,
                          let ts = d["timestamp"] as? Timestamp else { return nil }
                    return PostComment(
                        id: doc.documentID,
                        uid: uid,
                        displayName: d["displayName"] as? String ?? "",
                        text: text,
                        timestamp: ts.dateValue(),
                        replyToUID: d["replyToUID"] as? String,
                        replyToName: d["replyToName"] as? String,
                        replyToCommentID: d["replyToCommentID"] as? String
                    )
                } ?? []
                DispatchQueue.main.async {
                    let prev = self.comments.count
                    self.comments = loaded
                    self.isLoading = false
                    let delta = loaded.count - prev
                    if delta != 0 && prev > 0 { self.onCountChange?(delta) }
                }
            }
    }

    private func sendComment() async {
        let text = commentText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }

        let db = Firestore.firestore()
        var data: [String: Any] = [
            "uid":         myUID,
            "displayName": myDisplayName,
            "text":        text,
            "timestamp":   FieldValue.serverTimestamp()
        ]
        if let reply = replyTo {
            data["replyToUID"]       = reply.uid
            data["replyToName"]      = reply.displayName
            data["replyToCommentID"] = reply.id
        }
        _ = try? await db.collection("posts").document(postID)
            .collection("comments").addDocument(data: data)
        try? await db.collection("posts").document(postID)
            .updateData(["commentCount": FieldValue.increment(Int64(1))])

        await MainActor.run {
            commentText = ""
            replyTo = nil
        }
    }

    private func deleteComment(_ comment: PostComment) {
        let db = Firestore.firestore()
        Task {
            try? await db.collection("posts").document(postID)
                .collection("comments").document(comment.id).delete()
            try? await db.collection("posts").document(postID)
                .updateData(["commentCount": FieldValue.increment(Int64(-1))])
            onCountChange?(-1)
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let secs = Int(-date.timeIntervalSinceNow)
        if secs < 60 { return "now" }
        if secs < 3600 { return "\(secs / 60)m" }
        if secs < 86400 { return "\(secs / 3600)h" }
        return "\(secs / 86400)d"
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
                            ProfileImageView(imageName: "", size: 40)
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
