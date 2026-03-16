import Foundation
import ActivityKit

// Shared between the main Tuff app target and TuffLiveActivity widget extension.
// Both targets compile this file; ScreenTimeManager.swift (main target only)
// no longer redeclares this struct.
struct BlockTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var appCount: Int
    }
    var appCount: Int
}
