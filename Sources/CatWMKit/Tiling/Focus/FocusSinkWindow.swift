import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

package final class FocusSinkWindow: NSWindow {
    package override var canBecomeKey: Bool { true }
}
