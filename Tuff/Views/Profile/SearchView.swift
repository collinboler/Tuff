import SwiftUI
import FirebaseFirestore

struct UserSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SearchUser] = []
    @State private var isSearching = false

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
                            ProfileImageView(imageName: "", size: 40,
                                            borderColor: TuffColors.accent, borderWidth: 1.5)
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
    }

    private func search(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.count >= 2 else { results = []; return }
        isSearching = true
        Task {
            let db = Firestore.firestore()
            // Search by username prefix
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

            // Dedupe and sort
            var seen = Set<String>()
            found = found.filter { seen.insert($0.id).inserted }

            await MainActor.run {
                results = found
                isSearching = false
            }
        }
    }
}
