import SwiftUI

/// Displays a profile photo. Priority order:
///   1. `uiImage`  — locally held UIImage (current user, just-taken photo)
///   2. `photoURL` — remote URL string loaded via shared NSCache (league members)
///   3. `imageName` — asset-catalog image (legacy / placeholder)
///   4. System placeholder icon
struct ProfileImageView: View {
    let imageName: String
    var size: CGFloat = 44
    var uiImage: UIImage? = nil
    var photoURL: String? = nil

    var body: some View {
        Group {
            if let img = uiImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if photoURL != nil {
                CachedRemoteImage(urlString: photoURL, size: size)
            } else if UIImage(named: imageName) != nil {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundColor(Color(hex: "555555"))
    }
}

// Backed by RemoteImageLoader which uses a shared NSCache — the same image
// object is reused across every view that shows the same URL.
private struct CachedRemoteImage: View {
    let urlString: String?
    let size: CGFloat

    @StateObject private var loader = RemoteImageLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: "EEEEEE")
            }
        }
        .onAppear { loader.load(from: urlString) }
        .onChange(of: urlString) { _, newValue in
            loader.load(from: newValue)
        }
        .onDisappear { loader.cancel() }
    }
}
