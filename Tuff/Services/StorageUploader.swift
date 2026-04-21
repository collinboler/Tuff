import Foundation
import FirebaseStorage

enum StorageUploadError: LocalizedError {
    case uploadFailed(Error)
    case downloadURLFailed(Error)

    var errorDescription: String? {
        switch self {
        case .uploadFailed(let error):
            // Firebase sometimes surfaces the weird "Object ... does not exist"
            // error even when the file was written — reframe it so the user
            // isn't left reading a misleading message.
            let message = error.localizedDescription
            if message.lowercased().contains("does not exist") {
                return "Photo upload timed out while syncing. Please try again."
            }
            return "Photo upload failed: \(message)"
        case .downloadURLFailed(let error):
            return "Could not link photo: \(error.localizedDescription)"
        }
    }
}

/// Helpers for uploading photos to Firebase Storage reliably.
///
/// Firebase Storage's `downloadURL()` (and sometimes `putDataAsync`) occasionally
/// fails with "Object does not exist" immediately after a successful upload —
/// this is a known race in Firebase where the metadata index hasn't caught up.
/// Callers previously surfaced that directly as a user-facing error. These
/// helpers retry transient failures and, as a last resort, return a `gs://`
/// URL (which `RemoteImageLoader` and `HomeViewModel` already resolve to an
/// https download URL at read time) so that a successful upload is never
/// thrown away.
enum StorageUploader {
    /// Upload a JPEG blob to `profileImages/<uid>.jpg` and return a stable URL
    /// string suitable for storing in Firestore's `photoURL` field.
    static func uploadProfilePhoto(data: Data, uid: String) async throws -> String {
        let ref = Storage.storage().reference().child("profileImages/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        return try await upload(data: data, to: ref, metadata: metadata)
    }

    /// Generic upload with retries + `gs://` fallback.
    static func upload(data: Data, to ref: StorageReference, metadata: StorageMetadata) async throws -> String {
        try await performUpload(data: data, to: ref, metadata: metadata)

        // Try to resolve a download URL a few times. Firebase can take a
        // second or two to index newly-written objects.
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                let url = try await ref.downloadURL()
                return url.absoluteString
            } catch {
                lastError = error
                let delay = UInt64(300_000_000) * UInt64(1 << attempt) // 0.3, 0.6, 1.2, 2.4s
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        // The upload succeeded but we can't get an https URL right now.
        // Return the gs:// URL instead — readers already resolve it lazily.
        if !ref.bucket.isEmpty {
            return "gs://\(ref.bucket)/\(ref.fullPath)"
        }
        throw StorageUploadError.downloadURLFailed(lastError ?? NSError(
            domain: "TuffStorage", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown download URL error"]
        ))
    }

    /// Performs the actual `putDataAsync` with one retry for transient failures.
    private static func performUpload(data: Data, to ref: StorageReference, metadata: StorageMetadata) async throws {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                _ = try await ref.putDataAsync(data, metadata: metadata)
                return
            } catch {
                lastError = error
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
        }
        throw StorageUploadError.uploadFailed(lastError ?? NSError(
            domain: "TuffStorage", code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Unknown upload error"]
        ))
    }
}
