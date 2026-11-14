import AppKit
import CoreGraphics

package struct WorkspaceObservation {
    package struct Display {
        package let id: String
        package let frame: CGRect
        package let space: UInt64
        package let spaces: Set<UInt64>
    }

    package let displays: [Display]
    package let frames: [CGWindowID: CGRect]
    package let present: Set<CGWindowID>
    package let held: Set<CGWindowID>
    package var maximised: [CGWindowID: UInt64] = [:]
}
