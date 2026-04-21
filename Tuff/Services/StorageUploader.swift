import Foundation
import FirebaseStorage

enum StorageUploadError: LocalizedError {
    case uploadFailed(Error)
    case downloadURLFailed(Error)

    var errorDescription: String? {
        switch self {
        case .uploadFailed(let error):
            // "Object ... does not exist" after we've already tried to read
            // the file back means Storage Rules blocked access OR the bucket
            // isn't initialised — guide the user to the real fix.
            let message = error.localizedDescription
            if message.lowercased().contains("does not exist") ||
               message.lowercased().contains("permission") ||
               message.lowercased().contains("unauthorized") {
                return "Photo upload blocked by Firebase — check Storage rules & bucket."
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
    ///
    /// Firebase's `putDataAsync` occasionally throws "Object does not exist"
    /// even after the bytes made it to the server — the SDK's post-upload
    /// metadata read races with Storage's indexing. We treat that error as
    /// soft: first try to confirm the file exists via `downloadURL` /
    /// `getMetadata`. If either succeeds, the upload is fine. If both also
    /// fail we surface the original upload error to the caller.
    static func upload(data: Data, to ref: StorageReference, metadata: StorageMetadata) async throws -> String {
        let putError = await performUpload(data: data, to: ref, metadata: metadata)

        // Try to resolve a download URL a few times. If this succeeds, the
        // upload actually worked regardless of what `putDataAsync` reported.
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

        // downloadURL kept failing. Confirm the object exists via metadata —
        // if it does, we still consider the upload successful and hand back
        // a gs:// URL (RemoteImageLoader resolves gs:// lazily).
        if (try? await ref.getMetadata()) != nil, !ref.bucket.isEmpty {
            return "gs://\(ref.bucket)/\(ref.fullPath)"
        }

        // Neither downloadURL nor metadata could find the file.
        if let putError {
            throw StorageUploadError.uploadFailed(putError)
        }
        throw StorageUploadError.downloadURLFailed(lastError ?? NSError(
            domain: "TuffStorage", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown download URL error"]
        ))
    }

    /// Runs `putDataAsync` with a single retry for transient failures.
    /// Returns `nil` on success, or the last error encountered on failure —
    /// the caller decides whether to still treat the upload as successful
    /// based on whether the file actually landed on the server.
    private static func performUpload(data: Data, to ref: StorageReference, metadata: StorageMetadata) async -> Error? {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                _ = try await ref.putDataAsync(data, metadata: metadata)
                return nil
            } catch {
                lastError = error
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
        }
        return lastError ?? NSError(
            domain: "TuffStorage", code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Unknown upload error"]
        )
    }
}
