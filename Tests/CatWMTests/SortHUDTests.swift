import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

private final class SortHUDSurface: TilingSurface {
    var hud: [String] = []
    var inMode = false
    var showsTabDrop = false

    func start(_: WindowManager) {}
    func apply(_: Config) {}
    func showHUD(_ text: String, layout _: Layout?, on _: NSScreen?) { hud.append(text) }
    func warnHUD(_ text: String, on _: NSScreen?) { hud.append(text) }
    func leaveMode() {}
    var keybindsActive: Bool { false }
    var keysPaused: Bool { false }
    func setKeyTap(enabled _: Bool) {}
    func setKeyBinds(enabled _: Bool) {}
    func stop() {}
    func tilesDidChange(instant _: Bool) {}
    func splitSwapped(on _: String) {}
    func tabsDidChange(instant _: Bool) {}
    func batchTabChanges(_ changes: () -> Void) { changes() }
    func restackTabStrips() {}
    var revealedTabGroup: Int? { nil }
    func previewTabDrop(_: Window, at _: CGPoint) -> Bool { false }
    func endTabPreview(of _: CGWindowID) -> (group: Int, index: Int)? { nil }
    func showTabDropHint(over _: CGRect, adding _: Window) {}
    func hideTabDropHint() {}
    func followTabStrip(_: Int, at _: CGVector, lowest _: CGFloat) {}
    func endTabStripFollow() {}
    var watchesTitles: Bool { false }
    func titleChanged(_: Window) {}
    func windowForgotten(_: CGWindowID) {}
    func abandonOverview() {}
    func toggleOverview() {}
    func undoOverview() {}
    func refreshed(_: [Screen]) {}
    func openSwitcher(backward _: Bool) {}
    func focusChanged() {}
    func toggleFocusEffect(_: FocusEffect) {}
    var loginItem: (enabled: Bool, needsApproval: Bool) { (false, false) }
    func preview(_: String, _: String) -> Bool { false }
}

@Suite(.serialized) @MainActor struct SortHUDTests {
    @Test func aSortErrorReachesTheHUDOnlyWhenThatFeatureIsOn() async {
        #expect(await sortError(hud: false).isEmpty)
        #expect(await sortError(hud: true) == ["The previous Desktop action did not finish"])
    }

    private func sortError(hud: Bool) async -> [String] {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager { if !hud { $0.features.remove(.hud) } }
        let surface = SortHUDSurface()
        manager.surface = surface
        manager.monitorOf["2"] = screen.uuid
        manager.desktops.nativeSortNames = ["2"]
        manager.desktops.nativeCreationBusy = true
        let task = manager.finishSort(closing: [], goTo: nil, focus: false)
        task.cancel()
        await task.value
        return surface.hud
    }
}
