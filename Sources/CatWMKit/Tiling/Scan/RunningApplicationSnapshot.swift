import AppKit
import QuartzCore

package struct RunningApplicationSnapshot: Sendable {
    package let pid: pid_t
    package let bundleID: String?
    package let regular: Bool
    package let hidden: Bool

    package init(pid: pid_t, bundleID: String?, regular: Bool, hidden: Bool) {
        (self.pid, self.bundleID, self.regular, self.hidden) = (pid, bundleID, regular, hidden)
    }

    package static func read() -> [Self] {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return NSWorkspace.shared.runningApplications.compactMap { app in
            let pid = app.processIdentifier
            guard pid != getpid() else { return nil }
            let regular = app.activationPolicy == .regular
            return Self(pid: pid, bundleID: regular ? app.bundleIdentifier : nil,
                        regular: regular, hidden: regular && app.isHidden)
        }
    }
}
