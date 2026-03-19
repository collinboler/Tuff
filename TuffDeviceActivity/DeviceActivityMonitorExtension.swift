import DeviceActivity
import Foundation

class TuffDeviceActivityMonitor: DeviceActivityMonitor {

    private let groupID = "group.com.collinboler.tuff"

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        appendLog("start,\(activity.rawValue)")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        appendLog("end,\(activity.rawValue)")
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        appendLog("threshold,5,\(event.rawValue)")
    }

    /// Append a line to the shared log file.
    /// File-based writes avoid the iOS 17 CFPreferences crash that kills
    /// extensions reading UserDefaults in App Group containers.
    private func appendLog(_ entry: String) {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("monitor_log.txt") else { return }

        let line = "\(Int(Date().timeIntervalSince1970)),\(entry)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
