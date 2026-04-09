import ActivityKit
import WidgetKit
import SwiftUI

private let tuffGreen = Color(red: 0, green: 206/255, blue: 109/255)

// MARK: - Dynamic Island + Lock Screen Live Activity

@main
struct TuffLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BlockTimerAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (long press)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        tuffBadge(size: 28, fontSize: 14)
                        Text("TUFF")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.white)
                            .tracking(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isOnBreak, context.state.endDate > Date() {
                        Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                            .font(.system(size: 20, weight: .bold).monospacedDigit())
                            .foregroundColor(tuffGreen)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 4)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(tuffGreen)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Link(destination: URL(string: "tuff://block")!) {
                        HStack {
                            Image(systemName: context.state.isOnBreak ? "lock.open.fill" : "lock.fill")
                                .foregroundColor(tuffGreen)
                            Text(context.state.isOnBreak ? "Break active · Tap to manage" : "Apps locked · Tap to buy a break")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                tuffBadge(size: 20, fontSize: 10)
            } compactTrailing: {
                if context.state.isOnBreak, context.state.endDate > Date() {
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundColor(tuffGreen)
                        .frame(maxWidth: 48)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(tuffGreen)
                }
            } minimal: {
                tuffBadge(size: 16, fontSize: 8)
            }
            .widgetURL(URL(string: "tuff://block"))
            .keylineTint(tuffGreen)
        }
    }

    @ViewBuilder
    private func tuffBadge(size: CGFloat, fontSize: CGFloat) -> some View {
        Circle()
            .fill(tuffGreen)
            .frame(width: size, height: size)
            .overlay(
                Text("T")
                    .font(.system(size: fontSize, weight: .black))
                    .foregroundColor(.black)
            )
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<BlockTimerAttributes>) -> some View {
        Link(destination: URL(string: "tuff://block")!) {
            HStack(spacing: 14) {
                tuffBadge(size: 40, fontSize: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.isOnBreak ? "TUFF BREAK ACTIVE" : "TUFF")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(0.5)
                    Text(context.state.isOnBreak ? "Apps unlock until break ends" : "Apps are locked")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                if context.state.isOnBreak, context.state.endDate > Date() {
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                        .font(.system(size: 24, weight: .black).monospacedDigit())
                        .foregroundColor(tuffGreen)
                        .multilineTextAlignment(.trailing)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(tuffGreen)
                }
            }
            .padding(16)
        }
        .activityBackgroundTint(Color(white: 0.1))
        .activitySystemActionForegroundColor(.white)
    }
}
