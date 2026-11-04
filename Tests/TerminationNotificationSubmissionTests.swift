import Foundation

@main
struct TerminationNotificationSubmissionTests {
    static func main() {
        let immediate = TerminationNotificationSubmission()
        var result = "pending"
        immediate.complete { result = "submitted" }
        immediate.wait(timeout: 0.1) { result = "timeout" }
        precondition(result == "submitted", "Confirmed submission must not become a timeout")
        immediate.complete { result = "duplicate" }
        precondition(result == "submitted", "Ignore duplicate completion callbacks")

        let missing = TerminationNotificationSubmission()
        let started = Date()
        missing.wait(timeout: 0.03) { result = "timeout" }
        precondition(result == "timeout", "Missing completion must record timeout")
        precondition(Date().timeIntervalSince(started) < 0.5, "Waiting must be bounded")
        missing.complete { result = "late-success" }
        precondition(result == "late-success", "Late confirmation replaces the inconclusive timeout")

        let delayed = TerminationNotificationSubmission()
        let confirmed = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
            delayed.complete { confirmed.signal() }
        }
        var timedOut = false
        delayed.wait(timeout: 0.5) { timedOut = true }
        precondition(!timedOut && confirmed.wait(timeout: .now()) == .success,
                     "Wait for an asynchronous completion before returning")
        print("PASS: 6 termination notification submission checks")
    }
}
