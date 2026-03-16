import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Dynamic Island + Lock Screen Live Activity

@main
struct TuffLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BlockTimerAttributes.self) { context in
            // Lock screen / StandBy banner
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (long press)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: 0, green: 206/255, blue: 109/255))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text("T")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(.black)
                            )
                        Text("TUFF")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.white)
                            .tracking(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundColor(Color(red: 0, green: 206/255, blue: 109/255))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Link(destination: URL(string: "tuff://block")!) {
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(Color(red: 0, green: 206/255, blue: 109/255))
                            Text("Blocking \(context.state.appCount) app\(context.state.appCount == 1 ? "" : "s") · Tap to manage")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                // Compact: Tuff logo dot
                Circle()
                    .fill(Color(red: 0, green: 206/255, blue: 109/255))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text("T")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.black)
                    )
            } compactTrailing: {
                // Compact: countdown
                Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundColor(Color(red: 0, green: 206/255, blue: 109/255))
                    .frame(maxWidth: 48)
            } minimal: {
                // Minimal: just the dot
                Circle()
                    .fill(Color(red: 0, green: 206/255, blue: 109/255))
                    .frame(width: 16, height: 16)
            }
            .widgetURL(URL(string: "tuff://block"))
            .keylineTint(Color(red: 0, green: 206/255, blue: 109/255))
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<BlockTimerAttributes>) -> some View {
        Link(destination: URL(string: "tuff://block")!) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color(red: 0, green: 206/255, blue: 109/255))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text("T")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.black)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("TUFF IS BLOCKING")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(0.5)
                    Text("\(context.state.appCount) app\(context.state.appCount == 1 ? "" : "s") blocked")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                    .font(.system(size: 24, weight: .black).monospacedDigit())
                    .foregroundColor(Color(red: 0, green: 206/255, blue: 109/255))
                    .multilineTextAlignment(.trailing)
            }
            .padding(16)
        }
        .activityBackgroundTint(Color(white: 0.1))
        .activitySystemActionForegroundColor(.white)
    }
}
