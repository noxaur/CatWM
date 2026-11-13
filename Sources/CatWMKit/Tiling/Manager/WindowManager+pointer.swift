import AppKit

extension WindowManager {
    package func mouseLocation() -> CGPoint { backend.pointerLocation() }
    package func primaryButtonDown() -> Bool { backend.primaryButtonDown() }
    package func anyButtonDown() -> Bool { backend.anyButtonDown() }
}
