import AppKit

@MainActor package final class DesktopMenuBarLease {
    package let state: DesktopMenuBar.State
    private var panel: CatWMPanel?
    private var finished = false

    package init(state: DesktopMenuBar.State, panel: CatWMPanel?) {
        self.state = state
        self.panel = panel
    }

    package func finish() async {
        state.restore()
        let restored = await poll(0.2, every: 1_000_000) { self.state.isRestored }
        if restored { state.clear() }
        restore()
    }

    package func restore() {
        guard !finished else { return }
        finished = true
        let batch = WindowServerUpdates.shared.begin()
        defer { batch?.finish() }
        if let panel { DesktopMenuBarNative.orderOut(CGWindowID(panel.windowNumber)) }
        panel?.orderOut(nil)
        state.restore()
        DesktopMenuBarNative.alpha(state.space, -1)
        DesktopMenuBarCover.shared.recycle(panel)
        panel = nil
    }
}
