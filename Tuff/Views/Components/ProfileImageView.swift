import SwiftUI

struct ProfileImageView: View {
    let imageName: String
    var size: CGFloat = 44
    var borderColor: Color = TuffColors.accent
    var borderWidth: CGFloat = 2

    var body: some View {
        Group {
            if let _ = UIImage(named: imageName) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color(hex: "555555"))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(borderColor, lineWidth: borderWidth)
        )
    }
}
