import AppKit

package struct DesktopGuardLease {
    package enum Action: Equatable { case none, restore, finish }
    package private(set) var armed = true
    private var heartbeat: TimeInterval
    private let timeout: TimeInterval = 1.5

    package init(now: TimeInterval) { heartbeat = now }

    package mutating func accept(now: TimeInterval) -> Bool {
        guard armed else { return false }
        heartbeat = now
        return true
    }

    package mutating func receive(_ message: String, now: TimeInterval) -> Action {
        guard armed else { return .none }
        if message == "PING" { heartbeat = now }
        if message == "DONE" { armed = false; return .finish }
        return .none
    }

    package mutating func check(now: TimeInterval, parentExited: Bool = false) -> Action {
        guard armed, parentExited || now - heartbeat >= timeout else { return .none }
        armed = false
        return .restore
    }
}
