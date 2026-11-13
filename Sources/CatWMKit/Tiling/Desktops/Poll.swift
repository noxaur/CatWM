import Foundation
import QuartzCore

@MainActor package func poll(_ seconds: TimeInterval, every nanoseconds: UInt64 = 5_000_000,
                             while current: () -> Bool = { true }, until condition: () -> Bool) async -> Bool {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    while current() {
        if condition() { return true }
        guard ProcessInfo.processInfo.systemUptime < deadline, !Task.isCancelled else { return false }
        try? await Task.sleep(nanoseconds: nanoseconds) // style-ok: window server state has no change event
    }
    return false
}
