import Foundation
import ActivityKit

// Shared between the main Tuff app target and TuffLiveActivity widget extension.
// Both targets compile this file; ScreenTimeManager.swift (main target only)
// no longer redeclares this struct.
struct BlockTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// True while a break is active and apps are unlocked.
        var isOnBreak: Bool
        /// Only meaningful when isOnBreak == true.
        var endDate: Date
        var appCount: Int
    }
    var appCount: Int
}
