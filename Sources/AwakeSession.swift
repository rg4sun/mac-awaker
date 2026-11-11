import Foundation
import IOKit.pwr_mgt

/// Owns a temporary request to keep the display awake. It never edits a power,
/// screen saver or password preference. macOS also removes the request if this
/// process exits, including when the application crashes.
final class AwakeSession {
    enum SessionError: LocalizedError {
        case invalidDuration
        case powerRequestFailed(IOReturn)

        var errorDescription: String? {
            switch self {
            case .invalidDuration:
                return "Choose a keep-awake time greater than zero."
            case .powerRequestFailed(let code):
                return "macOS could not start the keep-awake request (code \(code))."
            }
        }
    }

    private(set) var assertionID: IOPMAssertionID?
    private(set) var startedAt: Date?
    private(set) var deadline: Date?
    private var deadlineUptime: TimeInterval?
    private var startedUptime: TimeInterval?

    var isActive: Bool { assertionID != nil }

    var elapsed: TimeInterval {
        guard let startedUptime else { return 0 }
        return max(0, ProcessInfo.processInfo.systemUptime - startedUptime)
    }

    var remaining: TimeInterval? {
        guard let deadlineUptime else { return nil }
        return max(0, deadlineUptime - ProcessInfo.processInfo.systemUptime)
    }

    /// A nil duration means the request lasts until the user stops it. Finite
    /// sessions also have a timeout enforced by the power service, independently
    /// of the application's main run loop.
    func start(for duration: TimeInterval? = nil) throws {
        if let duration, !duration.isFinite || duration <= 0 {
            throw SessionError.invalidDuration
        }

        var properties: [String: Any] = [
            kIOPMAssertionTypeKey: kIOPMAssertionTypePreventUserIdleDisplaySleep,
            kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
            kIOPMAssertionNameKey: "Mac Awaker: reading reference material",
            kIOPMAssertionDetailsKey: "The user has explicitly enabled the visible keep-awake control."
        ]

        if let duration {
            properties[kIOPMAssertionTimeoutKey] = duration
            properties[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionRelease
        }

        // Acquire the replacement first: a failed timer change must not silently
        // remove a working session or claim that an inactive request is active.
        var replacement = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &replacement)
        guard result == kIOReturnSuccess else {
            throw SessionError.powerRequestFailed(result)
        }

        stop()
        assertionID = replacement
        startedAt = Date()
        startedUptime = ProcessInfo.processInfo.systemUptime
        deadline = duration.map { Date().addingTimeInterval($0) }
        deadlineUptime = duration.map { ProcessInfo.processInfo.systemUptime + $0 }
    }

    func stop() {
        if let assertionID {
            // A finite request may already have been released by the system.
            // Releasing that expired identifier is harmless.
            IOPMAssertionRelease(assertionID)
        }
        assertionID = nil
        startedAt = nil
        startedUptime = nil
        deadline = nil
        deadlineUptime = nil
    }

    /// Reconciles the visible state with macOS. A sleep event or an expired
    /// system timeout must never leave a misleading active indicator behind.
    @discardableResult
    func refresh() -> Bool {
        guard let assertionID else { return false }
        if let remaining, remaining <= 0 {
            stop()
            return false
        }

        guard let properties = IOPMAssertionCopyProperties(assertionID)?.takeRetainedValue()
            as? [String: Any],
            let level = properties[kIOPMAssertionLevelKey] as? NSNumber,
            level.uint32Value == kIOPMAssertionLevelOn else {
            stop()
            return false
        }
        return true
    }

    deinit {
        stop()
    }
}
