import AppKit

package struct FloatState {
    package var floatFrames: [CGWindowID: CGRect] = [:]
    package var floatZoom: [CGWindowID: CGRect] = [:]
    package var savedOwnerOf: [CGWindowID: String] = [:]
    package var savedFloating: [CGWindowID: Bool] = [:]
}
