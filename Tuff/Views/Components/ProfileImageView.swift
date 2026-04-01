import SwiftUI

/// Displays a profile photo. Priority order:
///   1. `uiImage`  — locally held UIImage (current user, just-taken photo)
///   2. `photoURL` — remote URL string (league members loaded from Firestore)
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
            } else if let urlString = photoURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        Color(hex: "EEEEEE")
                    @unknown default:
                        placeholder
                    }
                }
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
