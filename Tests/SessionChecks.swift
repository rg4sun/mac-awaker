import Foundation
import IOKit.pwr_mgt

/// Integration checks use genuine system requests. Each scope releases its own
/// request and the test never edits an OS preference or triggers screen locking.
@main
struct SessionChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
        print("PASS: \(message)")
    }

    static func properties(_ id: IOPMAssertionID) -> [String: Any]? {
        IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any]
    }

    static func main() throws {
        let session = AwakeSession()
        defer { session.stop() }
        require(!session.isActive, "A new session starts off")

        try session.start()
        let firstID = session.assertionID!
        let activeProperties = properties(firstID)!
        require(activeProperties[kIOPMAssertionTypeKey] as? String == kIOPMAssertionTypePreventUserIdleDisplaySleep,
                "macOS holds a display-sleep request")
        require(session.refresh(), "The request is active in macOS")
        require(session.remaining == nil, "An unlimited session has no timer")

        do {
            try session.start(for: -1)
            require(false, "An invalid duration must be rejected")
        } catch AwakeSession.SessionError.invalidDuration {
            require(session.assertionID == firstID, "An invalid duration leaves the existing session intact")
        }

        try session.start(for: 2)
        let timedID = session.assertionID!
        require(timedID != firstID, "A timed session replaces the previous request")
        require(properties(firstID) == nil, "The replaced request is released")
        require(session.remaining != nil && session.remaining! > 0, "The countdown starts")
        require(properties(timedID)?[kIOPMAssertionTimeoutKey] != nil, "macOS enforces the timed session independently")

        // Wait for powerd, rather than invoking refresh first: this proves the
        // system timeout works independently of the application's timer.
        let limit = Date().addingTimeInterval(8)
        while properties(timedID) != nil && Date() < limit {
            Thread.sleep(forTimeInterval: 0.1)
        }
        require(properties(timedID) == nil, "macOS releases a timed request automatically")
        require(!session.refresh() && !session.isActive, "The visible session state follows timeout expiry")

        try session.start()
        let stoppedID = session.assertionID!
        session.stop()
        session.stop()
        require(!session.isActive && session.startedAt == nil, "Stopping is safe to repeat and clears state")
        require(properties(stoppedID) == nil, "Stopping releases the real macOS request")

        var cleanupID: IOPMAssertionID = 0
        do {
            let temporary = AwakeSession()
            try temporary.start()
            cleanupID = temporary.assertionID!
            withExtendedLifetime(temporary) {}
        }
        require(properties(cleanupID) == nil, "Session cleanup releases the request")
    }
}
