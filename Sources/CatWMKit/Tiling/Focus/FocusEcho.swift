import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

package struct FocusEcho {
    package static let window: TimeInterval = 0.4

    package let id: CGWindowID
    package let other: pid_t
    package let until: Date

    package init(id: CGWindowID, other: pid_t, now: Date = Date()) {
        self.id = id
        self.other = other
        until = now.addingTimeInterval(Self.window)
    }

    package func matches(_ pid: pid_t?, at now: Date = Date()) -> Bool { pid == other && now < until }
}
