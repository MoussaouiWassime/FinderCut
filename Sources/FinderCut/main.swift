import AppKit
import Foundation

// Single-instance guard: if FinderCut is already running, ask it to open Settings and exit.
if let bundleID = Bundle.main.bundleIdentifier {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != currentPID }

    if !otherInstances.isEmpty {
        DistributedNotificationCenter.default().postNotificationName(
            AppDelegate.reopenNotificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
