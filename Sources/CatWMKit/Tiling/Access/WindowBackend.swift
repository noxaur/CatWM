import AppKit
import ApplicationServices

package protocol WindowBackend: Sendable {
    func applications() -> [RunningApplicationSnapshot]
    func desktop(known: Set<CGWindowID>) -> WindowServerObservation
    func scan(_ job: WindowScanner.Job, discovered: (WindowScanner.AppScan) -> Void) -> WindowScanner.AppScan
    func focusedWindow(pid: pid_t) -> FocusReader.Result
    func screens() -> [Screen]
    func currentSpace(display: String) -> UInt64
    func isRunning(_ pid: pid_t) -> Bool
    func frontmostPID() -> pid_t?
    func frame(of window: Window) -> CGRect
    func setPosition(_ window: Window, _ point: CGPoint) -> Bool
    func setSize(_ window: Window, _ size: CGSize) -> Bool
    func blocksPlacement(_ window: Window) -> Bool
    func suspendEnhancedUI(_ pid: pid_t) -> Bool
    func resumeEnhancedUI(_ pid: pid_t)
    func focus(_ window: Window, ifCurrent: () -> Bool)
    func refreshCursor()
    func close(_ window: Window) -> String

    @MainActor func pointerLocation() -> CGPoint
    @MainActor func primaryButtonDown() -> Bool
    @MainActor func warpPointer(to point: CGPoint)
    @MainActor func post(keyCode: UInt16, flags: CGEventFlags, style: Hotkeys.PostStyle)
    @MainActor func postMouse(_ type: CGEventType, at point: CGPoint)
    @MainActor func serverFrame(of id: CGWindowID) -> CGRect?
    @MainActor func spaceList(display: String) -> Spaces.DisplaySpaces?
    @MainActor func desktopShortcut(_ number: Int) -> SystemShortcut.Combo?
    @MainActor func stepShortcut(right: Bool) -> SystemShortcut.Combo?
}

extension WindowBackend {
    @MainActor package func pointerLocation() -> CGPoint { .zero }
    @MainActor package func primaryButtonDown() -> Bool { NSEvent.pressedMouseButtons & 1 != 0 }
    @MainActor package func warpPointer(to _: CGPoint) { assertionFailure("\(Self.self) has no input seam") }
    @MainActor package func post(keyCode _: UInt16, flags _: CGEventFlags, style _: Hotkeys.PostStyle) {
        assertionFailure("\(Self.self) has no input seam")
    }
    @MainActor package func postMouse(_: CGEventType, at _: CGPoint) {
        assertionFailure("\(Self.self) has no input seam")
    }
    @MainActor package func serverFrame(of _: CGWindowID) -> CGRect? { nil }
    @MainActor package func spaceList(display _: String) -> Spaces.DisplaySpaces? { nil }
    @MainActor package func desktopShortcut(_: Int) -> SystemShortcut.Combo? { nil }
    @MainActor package func stepShortcut(right _: Bool) -> SystemShortcut.Combo? { nil }
}
