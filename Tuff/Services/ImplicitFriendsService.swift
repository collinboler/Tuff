import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Implicit-friends ledger.
///
/// We track every person you've shared a league with over the last 30 days so
/// the home carousel never goes empty just because a league expired. Entries
/// are kept under `users/{uid}/implicitFriends/{friendUid}` with a
/// `refreshedAt` timestamp; the carousel filters anything older than 30 days
/// at read time. Refreshing on every join (and on each leagues-listener
/// snapshot) means leagues you re-join keep your friends visible indefinitely,
/// while one-off leagues with strangers fade off after a month.
@MainActor
final class ImplicitFriendsService {
    static let shared = ImplicitFriendsService()

    private init() {}

    /// 30-day TTL used for both writes (we set `expiresAt = now + 30d`) and
    /// reads (anything older is filtered out at the call site).
    static let ttl: TimeInterval = 30 * 24 * 60 * 60

    private struct CachedEntry {
        var entry: ImplicitFriendEntry
        var refreshedAt: Date
    }

    /// Refresh implicit-friend entries for every other member of the given
    /// league. Called from `joinLeague` and `createLeague` immediately after
    /// the Firestore membership write succeeds.
    func refreshAfterJoin(leagueId: String) async {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        guard let leagueDoc = try? await db.collection("leagues").document(leagueId).getDocument(),
              let data = leagueDoc.data() else { return }
        await refreshFromMemberProfiles(myUid: myUid,
                                        memberProfiles: data["memberProfiles"] as? [[String: Any]] ?? [])
    }

    /// Sync implicit-friends for every member-profile across every league I'm
    /// in. Called whenever the leagues snapshot listener fires so we keep up
    /// with mid-season joins/edits.
    func refreshFromAllLeagues(_ leagues: [League]) async {
        guard let myUid = Auth.auth().currentUser?.uid else { return }

        var profilesByUid: [String: ImplicitFriendEntry] = [:]
        for league in leagues {
            for member in league.members {
                let friendUid = member.user.uid
                guard !friendUid.isEmpty, friendUid != myUid else { continue }
                profilesByUid[friendUid] = ImplicitFriendEntry(
                    uid: friendUid,
                    name: member.user.name,
                    username: member.user.username,
                    photoURL: member.user.photoURL,
                    paymentMethod: member.user.paymentMethod.rawValue,
                    paymentID: member.user.paymentID
                )
            }
        }

        await writeEntries(myUid: myUid, entries: Array(profilesByUid.values))
    }

    /// Live snapshot of my implicit-friends collection, filtered to entries
    /// refreshed in the last 30 days. The closure runs on the main actor.
    /// Returns the listener handle so callers can cancel.
    func observe(_ onChange: @escaping ([ImplicitFriendEntry]) -> Void) -> ListenerRegistration? {
        guard let myUid = Auth.auth().currentUser?.uid else { return nil }
        let cutoff = Date().addingTimeInterval(-Self.ttl)
        let db = Firestore.firestore()
        return db.collection("users").document(myUid)
            .collection("implicitFriends")
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else {
                    Task { @MainActor in onChange([]) }
                    return
                }
                let entries: [ImplicitFriendEntry] = docs.compactMap { doc in
                    let d = doc.data()
                    let refreshedAt = (d["refreshedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                    guard refreshedAt >= cutoff else { return nil }
                    return ImplicitFriendEntry(
                        uid: doc.documentID,
                        name: d["name"] as? String ?? "",
                        username: d["username"] as? String ?? "",
                        photoURL: d["photoURL"] as? String,
                        paymentMethod: d["paymentMethod"] as? String ?? PaymentMethod.none.rawValue,
                        paymentID: d["paymentID"] as? String ?? ""
                    )
                }
                Task { @MainActor in onChange(entries) }
            }
    }

    // MARK: - Writers

    private func refreshFromMemberProfiles(myUid: String, memberProfiles: [[String: Any]]) async {
        let entries: [ImplicitFriendEntry] = memberProfiles.compactMap { profile in
            guard let uid = profile["uid"] as? String, uid != myUid, !uid.isEmpty else { return nil }
            let methodRaw = profile["paymentMethod"] as? String ?? PaymentMethod.none.rawValue
            return ImplicitFriendEntry(
                uid: uid,
                name: profile["name"] as? String ?? "",
                username: profile["username"] as? String ?? "",
                photoURL: profile["photoURL"] as? String,
                paymentMethod: methodRaw,
                paymentID: profile["paymentID"] as? String ?? ""
            )
        }
        await writeEntries(myUid: myUid, entries: entries)
    }

    /// Mirrors entries to `users/{myUid}/implicitFriends/{friendUid}` (so I
    /// see them) AND to `users/{friendUid}/implicitFriends/{myUid}` (so they
    /// see me). The bidirectional write makes the home carousel populate the
    /// moment two people land in the same league together.
    private func writeEntries(myUid: String, entries: [ImplicitFriendEntry]) async {
        guard !entries.isEmpty else { return }
        let db = Firestore.firestore()
        let batch = db.batch()
        let now = Timestamp(date: Date())

        // Build my own profile once so we can mirror it to each friend.
        let myProfile: [String: Any] = await {
            guard let doc = try? await db.collection("users").document(myUid).getDocument(),
                  let data = doc.data() else { return ["uid": myUid] }
            return [
                "uid": myUid,
                "name": "\(data["firstName"] as? String ?? "") \(data["lastName"] as? String ?? "")"
                    .trimmingCharacters(in: .whitespaces),
                "username": data["username"] as? String ?? "",
                "photoURL": data["photoURL"] as? String ?? "",
                "paymentMethod": data["paymentMethod"] as? String ?? PaymentMethod.none.rawValue,
                "paymentID": data["paymentID"] as? String ?? ""
            ]
        }()

        for entry in entries {
            let myDocRef = db.collection("users").document(myUid)
                .collection("implicitFriends").document(entry.uid)
            batch.setData([
                "uid": entry.uid,
                "name": entry.name,
                "username": entry.username,
                "photoURL": entry.photoURL ?? "",
                "paymentMethod": entry.paymentMethod,
                "paymentID": entry.paymentID,
                "refreshedAt": now
            ], forDocument: myDocRef, merge: true)

            let theirDocRef = db.collection("users").document(entry.uid)
                .collection("implicitFriends").document(myUid)
            var mirrored = myProfile
            mirrored["refreshedAt"] = now
            batch.setData(mirrored, forDocument: theirDocRef, merge: true)
        }

        do {
            try await batch.commit()
        } catch {
            print("[Tuff] implicitFriends write failed: \(error.localizedDescription)")
        }
    }
}

struct ImplicitFriendEntry: Identifiable, Hashable {
    let uid: String
    let name: String
    let username: String
    let photoURL: String?
    let paymentMethod: String
    let paymentID: String

    var id: String { uid }
}
