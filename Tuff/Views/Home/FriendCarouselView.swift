import SwiftUI

struct FriendCarouselView: View {
    let users: [TuffUser]
    let currentUserId: UUID
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let centerX = geo.size.width / 2

            Canvas { context, size in
                // Draw the dark arc background (filmstrip)
                let arcCenter = CGPoint(x: size.width / 2, y: size.height + 60)
                let radius: CGFloat = 230
                let innerRadius: CGFloat = radius - 42
                let outerRadius: CGFloat = radius + 42

                var arcPath = Path()
                arcPath.addArc(center: arcCenter, radius: outerRadius,
                               startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                arcPath.addArc(center: arcCenter, radius: innerRadius,
                               startAngle: .degrees(340), endAngle: .degrees(200), clockwise: true)
                arcPath.closeSubpath()

                context.fill(arcPath, with: .color(Color(hex: "111111")))

                // Divider lines along the arc
                let slotCount = min(users.count, 9)
                for i in 0..<slotCount {
                    let progress = Double(i) / Double(max(slotCount - 1, 1))
                    let angle = Angle(degrees: 200 + 140 * progress)
                    let x1 = arcCenter.x + innerRadius * CGFloat(cos(angle.radians))
                    let y1 = arcCenter.y + innerRadius * CGFloat(sin(angle.radians))
                    let x2 = arcCenter.x + outerRadius * CGFloat(cos(angle.radians))
                    let y2 = arcCenter.y + outerRadius * CGFloat(sin(angle.radians))

                    var linePath = Path()
                    linePath.move(to: CGPoint(x: x1, y: y1))
                    linePath.addLine(to: CGPoint(x: x2, y: y2))

                    context.stroke(linePath, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
                }
            }

            // Overlay the avatar circles
            let totalItems = min(users.count, 9)
            let arcCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height + 60)
            let radius: CGFloat = 230

            ForEach(Array(users.prefix(9).enumerated()), id: \.element.id) { index, user in
                let progress = totalItems > 1
                    ? Double(index) / Double(totalItems - 1)
                    : 0.5
                let angle = Angle(degrees: 200 + 140 * progress)
                let x = arcCenter.x + radius * CGFloat(cos(angle.radians))
                let y = arcCenter.y + radius * CGFloat(sin(angle.radians))

                let centerIndex = totalItems / 2
                let isCenter = index == centerIndex
                let distFromCenter = abs(index - centerIndex)
                let size: CGFloat = isCenter ? 52 : max(30, 44 - CGFloat(distFromCenter) * 4)
                let isCurrentUser = user.id == currentUserId

                ProfileImageView(
                    imageName: user.imageName,
                    size: size,
                    borderColor: isCurrentUser ? TuffColors.accent : TuffColors.avatarRingInactive,
                    borderWidth: isCenter ? 3 : 2
                )
                .shadow(color: isCenter ? TuffColors.avatarGlow : .clear, radius: 8)
                .position(x: x, y: y)
            }
        }
    }
}
