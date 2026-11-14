import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite @MainActor struct MouseResizeTests {
    private struct Rig {
        let manager: WindowManager, state: ScreenState, windows: [Window], screen: Screen
    }

    private func rig(mainCount: Int) -> Rig {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = WindowManager(backend: fake, config: .parse(defaultText))
        manager.config.windowMargins = false
        manager.shown[screen.uuid] = "1"
        let windows = (1...3).map {
            Window(id: CGWindowID($0), element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        }
        for window in windows {
            manager.windows[window.id] = window
            manager.order.append(window.id)
            manager.model.assign(window.id, to: "1")
            manager.visible.insert(window.id)
        }
        let state = manager.state(for: screen)
        (state.layout, state.ratio, state.mainCount) = (.tall, 0.5, mainCount)
        return Rig(manager: manager, state: state, windows: windows, screen: screen)
    }

    private func dragMainEdge(_ rig: Rig, by delta: CGFloat) throws -> CGRect {
        let slot = try #require(rig.manager.layoutTargets([1, 2, 3], rig.state, on: rig.screen)?[1])
        rig.windows[0].remember(CGRect(x: slot.minX, y: slot.minY, width: slot.width + delta, height: slot.height))
        rig.manager.applyMouseResize(rig.windows[0], on: rig.screen)
        return slot
    }

    @Test func draggingTheMainWindowsEdgeSetsTheRatio() throws {
        let rig = rig(mainCount: 1)
        let slot = try dragMainEdge(rig, by: 100)
        let gap = rig.manager.windowGap(count: 3, on: rig.screen)
        let total = rig.manager.usableRect(rig.screen).width + gap
        #expect(abs(rig.state.ratio - (slot.width + 100 + gap) / total) < 0.001)
    }

    @Test func aMainCountBelowOneStillCountsOneMainWindow() throws {
        let rig = rig(mainCount: 0)
        _ = try dragMainEdge(rig, by: 100)
        #expect(rig.state.ratio > 0.5)
    }
}

@Suite struct SplitGeometryTests {
    @Test func theMainCountStaysBetweenOneAndTheWindowCount() {
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)
        #expect(SplitDivider.split(.tall, mainCount: 0, count: 3, in: rect)?.mains == 1)
        #expect(SplitDivider.split(.tall, mainCount: 3, count: 3, in: rect) == nil)
        #expect(SplitDivider.split(.bsp, mainCount: 2, count: 3, in: rect)?.mains == 1)
    }
}
