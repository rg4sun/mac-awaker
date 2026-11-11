import AppKit

// Launch Services normally reuses an existing instance. Also guard direct
// executable launches so two copies cannot show conflicting awake indicators.
let application = NSApplication.shared
let bundleID = Bundle.main.bundleIdentifier ?? "local.rgtech.macawaker"
let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

if existing == nil {
    let delegate = AppDelegate()
    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    withExtendedLifetime(delegate) {
        application.run()
    }
}
