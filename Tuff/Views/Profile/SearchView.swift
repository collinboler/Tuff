import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - User Search

struct UserSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SearchUser] = []
    @State private var isSearching = false
    @State private var sentRequests: Set<String> = []
    @State private var friendUids: Set<String> = []

    struct SearchUser: Identifiable {
        let id: String  // Firebase uid
        let name: String
        let username: String
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(TuffColors.textSecondary)
                    TextField("Search by username or name...", text: $query)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, val in search(val) }
                    if !query.isEmpty {
                        Button { query = ""; results = [] } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(TuffColors.textSecondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(hex: "F5F5F5"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if isSearching {
                    ProgressView().padding(.top, 40)
                    Spacer()
                } else if results.isEmpty && !query.isEmpty {
                    VStack(spacing: 8) {
                        Spacer().frame(height: 60)
                        Text("No users found")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(TuffColors.textSecondary)
                    }
                    Spacer()
                } else {
                    List(results) { user in
                        HStack(spacing: 12) {
                            ProfileImageView(imageName: "", size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name.uppercased())
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                                    .tracking(0.3)
                                if !user.username.isEmpty {
                                    Text("@\(user.username)")
                                        .font(.system(size: 12))
                                        .foregroundColor(TuffColors.textSecondary)
                                }
                            }
                            Spacer()
                            addFriendButton(for: user)
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
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .colorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(TuffColors.accent)
                }
            }
        }
        .onAppear {
            loadSentRequests()
            loadFriendUids()
        }
    }

    @ViewBuilder
    private func addFriendButton(for user: SearchUser) -> some View {
        let myUid = Auth.auth().currentUser?.uid ?? ""
        if user.id == myUid {
            EmptyView()
        } else if friendUids.contains(user.id) {
            Text("Your Friend")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(TuffColors.textSecondary)
        } else {
            let sent = sentRequests.contains(user.id)
            Button {
                if !sent { sendFriendRequest(to: user) }
            } label: {
                Text(sent ? "Requested" : "Add Friend")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(sent ? TuffColors.textSecondary : TuffColors.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule().stroke(
                            sent ? Color.gray.opacity(0.35) : TuffColors.accent,
                            lineWidth: 1.5
                        )
                    )
            }
            .disabled(sent)
        }
    }

    private func loadFriendUids() {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        Task {
            let db = Firestore.firestore()
            let snap = try? await db.collection("users").document(myUid)
                .collection("friends").getDocuments()
            let ids = snap?.documents.map { $0.documentID } ?? []
            await MainActor.run { friendUids = Set(ids) }
        }
    }

    private func loadSentRequests() {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        Task {
            let db = Firestore.firestore()
            let snap = try? await db.collection("friendRequests")
                .whereField("fromUid", isEqualTo: myUid)
                .getDocuments()
            let ids = snap?.documents.compactMap { $0.data()["toUid"] as? String } ?? []
            await MainActor.run { sentRequests = Set(ids) }
        }
    }

    private func sendFriendRequest(to user: SearchUser) {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        sentRequests.insert(user.id)
        Task {
            let db = Firestore.firestore()
            let myDoc = try? await db.collection("users").document(myUid).getDocument()
            let d = myDoc?.data() ?? [:]
            let myName = "\(d["firstName"] as? String ?? "") \(d["lastName"] as? String ?? "")"
                .trimmingCharacters(in: .whitespaces)
            let myUsername = d["username"] as? String ?? ""
            try? await db.collection("friendRequests").addDocument(data: [
                "fromUid": myUid,
                "toUid": user.id,
                "fromName": myName,
                "fromUsername": myUsername,
                "status": "pending",
                "createdAt": FieldValue.serverTimestamp()
            ])
        }
    }

    private func search(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.count >= 2 else { results = []; return }
        isSearching = true
        Task {
            let db = Firestore.firestore()
            let byUsername = try? await db.collection("users")
                .whereField("username", isGreaterThanOrEqualTo: trimmed)
                .whereField("username", isLessThan: trimmed + "\u{f8ff}")
                .limit(to: 10)
                .getDocuments()

            var found: [SearchUser] = byUsername?.documents.compactMap { doc in
                let d = doc.data()
                let first = d["firstName"] as? String ?? ""
                let last  = d["lastName"]  as? String ?? ""
                let uname = d["username"]  as? String ?? ""
                let name  = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty || !uname.isEmpty else { return nil }
                return SearchUser(id: doc.documentID, name: name, username: uname)
            } ?? []

            var seen = Set<String>()
            found = found.filter { seen.insert($0.id).inserted }

            await MainActor.run {
                results = found
                isSearching = false
            }
        }
    }
}

// MARK: - Friends List

struct FriendsListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [FriendEntry] = []
    @State private var isLoading = true
    @State private var friendToRemove: FriendEntry? = nil

    struct FriendEntry: Identifiable {
        let id: String
        let name: String
        let username: String
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if friends.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "person.2")
                            .font(.system(size: 48))
                            .foregroundColor(Color(hex: "E0E0E0"))
                        Text("No friends yet")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                        Text("Join leagues to connect with others.")
                            .font(.system(size: 14))
                            .foregroundColor(TuffColors.textSecondary)
                        Spacer()
                    }
                } else {
                    List(friends) { friend in
                        HStack(spacing: 12) {
                            ProfileImageView(imageName: "", size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.name.uppercased())
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                                    .tracking(0.3)
                                if !friend.username.isEmpty {
                                    Text("@\(friend.username)")
                                        .font(.system(size: 12))
                                        .foregroundColor(TuffColors.textSecondary)
                                }
                            }
                            Spacer()
                            Button { friendToRemove = friend } label: {
                                Text("Remove")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .overlay(Capsule().stroke(Color.gray.opacity(0.4), lineWidth: 1.2))
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
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .colorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(TuffColors.accent)
                }
            }
        }
        .onAppear { loadFriends() }
        .alert(
            "Remove Friend",
            isPresented: Binding(
                get: { friendToRemove != nil },
                set: { if !$0 { friendToRemove = nil } }
            ),
            presenting: friendToRemove
        ) { friend in
            Button("Remove", role: .destructive) { removeFriend(friend) }
            Button("Cancel", role: .cancel) { friendToRemove = nil }
        } message: { friend in
            Text("Remove \(friend.name.isEmpty ? "this friend" : friend.name) from your friends?")
        }
    }

    private func removeFriend(_ friend: FriendEntry) {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        friends.removeAll { $0.id == friend.id }
        friendToRemove = nil
        Task {
            let db = Firestore.firestore()
            try? await db.collection("users").document(myUid)
                .collection("friends").document(friend.id).delete()
            try? await db.collection("users").document(friend.id)
                .collection("friends").document(myUid).delete()
            // Mark any accepted friend request as removed
            let snap = try? await db.collection("friendRequests")
                .whereField("status", isEqualTo: "accepted")
                .getDocuments()
            for doc in snap?.documents ?? [] {
                let d = doc.data()
                let from = d["fromUid"] as? String ?? ""
                let to   = d["toUid"]   as? String ?? ""
                if (from == myUid && to == friend.id) || (from == friend.id && to == myUid) {
                    try? await db.collection("friendRequests").document(doc.documentID).delete()
                }
            }
        }
    }

    private func loadFriends() {
        guard let myUid = Auth.auth().currentUser?.uid else { isLoading = false; return }
        Task {
            let db = Firestore.firestore()
            // Find unique league co-members
            let snap = try? await db.collection("leagues")
                .whereField("memberUids", arrayContains: myUid)
                .getDocuments()
            var friendUids = Set<String>()
            for doc in snap?.documents ?? [] {
                let uids = doc.data()["memberUids"] as? [String] ?? []
                for u in uids where u != myUid { friendUids.insert(u) }
            }
            // Fetch profiles
            var entries: [FriendEntry] = []
            for uid in friendUids {
                if let doc = try? await db.collection("users").document(uid).getDocument(),
                   let d = doc.data() {
                    let first = d["firstName"] as? String ?? ""
                    let last  = d["lastName"]  as? String ?? ""
                    let name  = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
                    let uname = d["username"] as? String ?? ""
                    entries.append(FriendEntry(id: uid, name: name.isEmpty ? uname : name, username: uname))
                }
            }
            entries.sort { $0.name < $1.name }
            await MainActor.run {
                friends = entries
                isLoading = false
            }
        }
    }
}
