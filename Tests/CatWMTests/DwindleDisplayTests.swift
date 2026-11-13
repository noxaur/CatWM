import AppKit
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct DwindleDisplayTests {
    private let area = CGRect(x: 0, y: 0, width: 1600, height: 900)

    @Test(arguments: [false, true])
    func sharedSpacesKeepATreePerDisplay(rightHasAWindow: Bool) async throws {
        let fake = FakeBackend()
        let left = fake.addScreen(frame: area, visible: area)
        let right = fake.addScreen(frame: area.offsetBy(dx: 1600, dy: 0), visible: area.offsetBy(dx: 1600, dy: 0))
        let ids = ([-531, -532, -533] as [pid_t]).map {
            fake.addWindow(pid: $0, frame: CGRect(x: 50, y: 50, width: 600, height: 400))
        }
        let manager = fake.makeManager { $0.layouts = [.dwindle] }
        #expect(await fake.settle(manager))
        manager.config.virtualWorkspaces = true
        manager.desktops.nativeCatalog.sharedSpaces = true
        for id in ids { manager.model.assign(id, to: "1") }
        manager.shown = [left.uuid: "1", right.uuid: "1"]
        manager.displayOf = [ids[0]: left.uuid, ids[1]: left.uuid, ids[2]: right.uuid]
        if !rightHasAWindow { manager.visible.remove(ids[2]) }
        let leftIDs = manager.tiled(on: left), rightIDs = manager.tiled(on: right)
        try #require(leftIDs.count == 2 && rightIDs.count == (rightHasAWindow ? 1 : 0))
        let screenState = manager.state(for: left)
        #expect(screenState === manager.state(for: right))

        _ = manager.layoutTargets(leftIDs, screenState, on: left)
        #expect(manager.withDwindle(on: left) { tree in tree.setRootRatio(0.7, in: area) })
        for _ in 0..<2 {
            _ = manager.layoutTargets(rightIDs, screenState, on: right)
            _ = manager.layoutTargets(leftIDs, screenState, on: left)
        }
        #expect(ratios(manager.dwindle(on: left)) == [0.7])
        #expect(manager.dwindle(on: right).ids == rightIDs)
    }

    @Test func aWindowArrivingOnAnotherWorkspaceJoinsItsStack() async throws {
        let fake = FakeBackend()
        let left = fake.addScreen(frame: area, visible: area)
        let other = area.offsetBy(dx: 1600, dy: 0)
        let right = fake.addScreen(frame: other, visible: other)
        let focused = fake.addWindow(pid: -541, frame: CGRect(x: 50, y: 50, width: 600, height: 400))
        for pid in [-542, -543] as [pid_t] {
            fake.addWindow(pid: pid, frame: CGRect(x: 1650, y: 50, width: 600, height: 400))
        }
        let manager = fake.makeManager { $0.layouts = [.dwindle, .tall] }
        #expect(await fake.settle(manager))
        manager.setLayout(.tall, on: right)
        manager.order = [focused] + manager.order.filter { $0 != focused }
        #expect(await fake.settle(manager))
        try await focus(focused, in: fake, manager: manager)
        let stack = manager.tiled(on: right)
        try #require(manager.tiled(on: left) == [focused] && stack.count == 2)

        let arrival = fake.addWindow(pid: -544, frame: CGRect(x: 1700, y: 100, width: 600, height: 400))
        #expect(await fake.settle(manager))
        #expect(manager.tiled(on: right) == stack + [arrival])
    }

    @Test func aTreeSurvivesADisplayConnectingAndDisconnecting() async throws {
        let fake = FakeBackend()
        let left = fake.addScreen(frame: area, visible: area)
        let ids = ([-551, -552] as [pid_t]).map {
            fake.addWindow(pid: $0, frame: CGRect(x: 50, y: 50, width: 600, height: 400))
        }
        let manager = fake.makeManager { $0.layouts = [.dwindle] }
        #expect(await fake.settle(manager))
        let workspace = try #require(manager.shown[left.uuid])
        manager.config.virtualWorkspaces = true
        for id in ids { manager.displayOf[id] = left.uuid }
        let screenState = manager.state(for: left)
        _ = manager.layoutTargets(ids, screenState, on: left)
        #expect(manager.withDwindle(on: left) { tree in tree.setRootRatio(0.7, in: area) })

        let other = area.offsetBy(dx: 1600, dy: 0)
        let right = fake.addScreen(frame: other, visible: other)
        manager.desktops.nativeCatalog.sharedSpaces = true
        manager.shown[right.uuid] = workspace
        for screen in [left, right] { _ = manager.layoutTargets(manager.tiled(on: screen), screenState, on: screen) }
        #expect(ratios(manager.dwindle(on: left)) == [0.7])

        fake.removeScreen(right)
        manager.desktops.nativeCatalog.sharedSpaces = false
        manager.shown[right.uuid] = nil
        _ = manager.layoutTargets(ids, screenState, on: left)
        #expect(ratios(manager.dwindle(on: left)) == [0.7])

        let moved = fake.addScreen(frame: other, visible: other)
        manager.shown = [left.uuid: "elsewhere", moved.uuid: workspace]
        _ = manager.layoutTargets(ids, screenState, on: moved)
        #expect(ratios(manager.dwindle(on: moved)) == [0.7])
    }

    @Test func anArrivalOnTheSameWorkspaceButAnotherDisplayJoinsItsOwnDisplay() async throws {
        let fake = FakeBackend()
        let left = fake.addScreen(frame: area, visible: area)
        let other = area.offsetBy(dx: 1600, dy: 0)
        let right = fake.addScreen(frame: other, visible: other)
        let ids = ([-561, -562, -563] as [pid_t]).map {
            fake.addWindow(pid: $0, frame: CGRect(x: 50, y: 50, width: 600, height: 400))
        }
        let manager = fake.makeManager { $0.layouts = [.dwindle] }
        #expect(await fake.settle(manager))
        try await focus(ids[0], in: fake, manager: manager)
        manager.config.virtualWorkspaces = true
        manager.desktops.nativeCatalog.sharedSpaces = true
        let arrival: CGWindowID = 99
        for id in ids + [arrival] { manager.model.assign(id, to: "1") }
        manager.shown = [left.uuid: "1", right.uuid: "1"]
        manager.displayOf = [ids[0]: left.uuid, ids[1]: right.uuid, ids[2]: right.uuid, arrival: right.uuid]
        manager.order = ids

        manager.orderArrivals([arrival], firstRun: false)
        #expect(manager.order == ids + [arrival])
    }

    @Test func aFloatingFocusedWindowDoesNotAnchorAnArrival() async throws {
        let fake = FakeBackend()
        fake.addScreen(frame: area, visible: area)
        let ids = ([-571, -572, -573] as [pid_t]).map {
            fake.addWindow(pid: $0, frame: CGRect(x: 50, y: 50, width: 600, height: 400))
        }
        let manager = fake.makeManager { $0.layouts = [.dwindle] }
        #expect(await fake.settle(manager))
        manager.setFloating(true, for: try #require(manager.windows[ids[1]]))
        manager.order = ids
        #expect(await fake.settle(manager))
        try await focus(ids[1], in: fake, manager: manager)

        let arrival = fake.addWindow(pid: -574, frame: CGRect(x: 300, y: 300, width: 600, height: 400))
        #expect(await fake.settle(manager))
        #expect(manager.order == ids + [arrival])
    }
}
