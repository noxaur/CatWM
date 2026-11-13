import AppKit
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct DwindleTests {
    private let area = CGRect(x: 0, y: 0, width: 1600, height: 900)

    private func focus(_ id: CGWindowID, in fake: FakeBackend, manager: WindowManager) async throws {
        fake.userFocuses(id)
        manager.handle(kAXFocusedWindowChangedNotification, try #require(fake.element(id)))
        #expect(await fake.wait(manager) { manager.focusRequests.reportedFocus?.id == id })
    }

    @Test func eachWindowSplitsThePreviousOneAlongItsLongerSide() {
        var tree = DwindleTree()
        tree.sync([1, 2, 3])
        #expect(tree.frames(in: area) == [
            CGRect(x: 0, y: 0, width: 800, height: 900),
            CGRect(x: 800, y: 0, width: 800, height: 450),
            CGRect(x: 800, y: 450, width: 800, height: 450)
        ])
    }

    @Test func aNewWindowSplitsItsPredecessorAndAClosedOneCollapses() {
        var tree = DwindleTree()
        tree.sync([1, 2, 3])
        tree.sync([1, 4, 2, 3])
        let frames = tree.frames(in: area)
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 800, height: 450))
        #expect(frames[1] == CGRect(x: 0, y: 450, width: 800, height: 450))
        tree.sync([1, 2, 3])
        #expect(tree.frames(in: area)[0] == CGRect(x: 0, y: 0, width: 800, height: 900))
        tree.sync([])
        #expect(tree.root == nil)
    }

    @Test func togglesplitSwapsplitAndResizeChangeOnlyTheirSplit() {
        var tree = DwindleTree()
        tree.sync([1, 2, 3])
        tree.toggleSplit(at: 2, in: area)
        #expect(tree.frames(in: area)[1] == CGRect(x: 800, y: 0, width: 400, height: 900))
        tree.swapSplit(at: 2, in: area)
        #expect(tree.frames(in: area)[1] == CGRect(x: 1200, y: 0, width: 400, height: 900))
        tree.resize(at: 0, by: CGSize(width: 160, height: 0), in: area)
        #expect(tree.frames(in: area)[0].width == 960)
        tree.resize(at: 0, by: CGSize(width: 10000, height: 0), in: area)
        #expect(tree.frames(in: area)[0].width == 1440)
    }

    @Test func minimumSizesFlipAnAutomaticSplitOrMoveItsRatio() {
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 900)
        var tree = DwindleTree()
        tree.sync([1, 2])
        let free = tree.frames(in: rect)
        tree.sync([1, 2], minimums: [CGSize(width: 600, height: 0), CGSize(width: 600, height: 0)])
        #expect(tree.frames(in: rect) == [
            CGRect(x: 0, y: 0, width: 1000, height: 450), CGRect(x: 0, y: 450, width: 1000, height: 450)
        ])
        tree.sync([1, 2], minimums: [CGSize(width: 700, height: 0), .zero])
        #expect(tree.frames(in: rect)[0].width == 700)
        tree.sync([1, 2], minimums: [CGSize(width: 900, height: 600), CGSize(width: 900, height: 600)])
        #expect(tree.frames(in: rect) == free)
    }

    @Test func resizeAndTogglesplitFollowTheDirectionTheMinimumsChose() {
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 900)
        let stacked = [CGRect(x: 0, y: 0, width: 1000, height: 450), CGRect(x: 0, y: 450, width: 1000, height: 450)]
        var tree = DwindleTree()
        tree.sync([1, 2], minimums: Array(repeating: CGSize(width: 600, height: 0), count: 2))
        #expect(tree.frames(in: rect) == stacked)
        tree.resize(at: 0, by: CGSize(width: 100, height: 0), in: rect)
        #expect(tree.frames(in: rect) == stacked)
        tree.toggleSplit(at: 1, in: rect)
        tree.toggleSplit(at: 1, in: rect)
        #expect(tree.frames(in: rect) == stacked)

        tree.sync([1, 2])
        #expect(tree.frames(in: rect)[1] == CGRect(x: 500, y: 0, width: 500, height: 900))
        tree.toggleSplit(at: 1, in: rect)
        #expect(tree.frames(in: rect) == stacked)
    }

    @Test func theManagerTilesWithTheTreeAndAppliesSplitCommands() async throws {
        let fake = FakeBackend()
        fake.addScreen(frame: area, visible: area)
        let first = fake.addWindow(pid: -501, frame: CGRect(x: 50, y: 50, width: 600, height: 400))
        let second = fake.addWindow(pid: -502, frame: CGRect(x: 700, y: 50, width: 600, height: 400))
        let manager = fake.makeManager { $0.layouts = [.dwindle] }
        #expect(await fake.settle(manager))
        let (lead, other) = fake.frame(of: first).minX == 0 ? (first, second) : (second, first)
        #expect(fake.frame(of: lead) == CGRect(x: 0, y: 0, width: 800, height: 900))
        #expect(fake.frame(of: other) == CGRect(x: 800, y: 0, width: 800, height: 900))

        #expect(manager.changeDwindle(of: try #require(manager.windows[other])) { $0.toggleSplit(at: $1, in: $2) })
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: lead) == CGRect(x: 0, y: 0, width: 1600, height: 450))
        #expect(fake.frame(of: other) == CGRect(x: 0, y: 450, width: 1600, height: 450))

        try await focus(lead, in: fake, manager: manager)
        manager.dispatch("resizeactive", "0 90")
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: lead).height == 540)
        #expect(fake.frame(of: other) == CGRect(x: 0, y: 540, width: 1600, height: 360))
    }

    @Test func aNewWindowSplitsTheFocusedOne() async throws {
        let fake = FakeBackend()
        fake.addScreen(frame: area, visible: area)
        let first = fake.addWindow(pid: -511, frame: CGRect(x: 50, y: 50, width: 600, height: 400))
        let second = fake.addWindow(pid: -512, frame: CGRect(x: 700, y: 50, width: 600, height: 400))
        let manager = fake.makeManager { $0.layouts = [.dwindle] }
        #expect(await fake.settle(manager))
        let lead = fake.frame(of: first).minX == 0 ? first : second
        try await focus(lead, in: fake, manager: manager)

        let third = fake.addWindow(pid: -513, frame: CGRect(x: 300, y: 300, width: 600, height: 400))
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: lead) == CGRect(x: 0, y: 0, width: 800, height: 450))
        #expect(fake.frame(of: third) == CGRect(x: 0, y: 450, width: 800, height: 450))
    }

    private struct Tiles {
        let fake: FakeBackend
        let manager: WindowManager
        let screen: Screen
        let ids: [CGWindowID]
        let clock: FakeClock

        @MainActor func settle() async {
            #expect(await fake.settle(manager))
            clock.advance(by: 1)
            #expect(await fake.settle(manager))
            clock.advance(by: 1)
        }
    }

    private func threeTiles() async throws -> Tiles {
        let fake = FakeBackend()
        let screen = fake.addScreen(frame: area, visible: area)
        for pid in [-521, -522, -523] as [pid_t] {
            fake.addWindow(pid: pid, frame: CGRect(x: 50, y: 50, width: 600, height: 400))
        }
        let clock = FakeClock()
        let manager = fake.makeManager({ $0.layouts = [.dwindle] }, clock: clock)
        await Tiles(fake: fake, manager: manager, screen: screen, ids: [], clock: clock).settle()
        let ids = manager.tiled(on: screen)
        try #require(ids.count == 3)
        return Tiles(fake: fake, manager: manager, screen: screen, ids: ids, clock: clock)
    }

    private func drag(_ id: CGWindowID, to frame: CGRect, in tiles: Tiles) async throws {
        try #require(!tiles.manager.animator.isBusy(id))
        tiles.fake.userMoves(id, to: frame)
        tiles.manager.drags[id] = true
        tiles.manager.mouseUp()
        await tiles.settle()
    }

    private func ratios(_ tree: DwindleTree) -> [CGFloat] {
        var out: [CGFloat] = [], node = tree.root
        while case .split(let split)? = node {
            out.append((split.ratio * 1e6).rounded() / 1e6)
            node = split.second
        }
        return out
    }

    @Test func draggingATileEdgeMovesTheSplitThatEdgeBelongsTo() async throws {
        let tiles = try await threeTiles()
        let (fake, manager, screen, ids) = (tiles.fake, tiles.manager, tiles.screen, tiles.ids)
        #expect(ids.map(fake.frame(of:)) == [
            CGRect(x: 0, y: 0, width: 800, height: 900),
            CGRect(x: 800, y: 0, width: 800, height: 450),
            CGRect(x: 800, y: 450, width: 800, height: 450)
        ])

        try await drag(ids[0], to: CGRect(x: 0, y: 0, width: 1000, height: 900), in: tiles)
        #expect(ratios(manager.dwindle(on: screen)) == [0.625, 0.5])
        #expect(fake.frame(of: ids[1]) == CGRect(x: 1000, y: 0, width: 600, height: 450))

        try await drag(ids[1], to: CGRect(x: 1000, y: 0, width: 600, height: 600), in: tiles)
        #expect(ratios(manager.dwindle(on: screen)) == [0.625, 0.666667])
        #expect(fake.frame(of: ids[2]) == CGRect(x: 1000, y: 600, width: 600, height: 300))

        try await drag(ids[1], to: CGRect(x: 800, y: 0, width: 800, height: 600), in: tiles)
        #expect(ratios(manager.dwindle(on: screen)) == [0.5, 0.666667])
        #expect(fake.frame(of: ids[0]) == CGRect(x: 0, y: 0, width: 800, height: 900))
    }

    @Test func aDraggedEdgeStopsAtTheNeighboursMinimumAndTheRatioLimit() async throws {
        let tiles = try await threeTiles()
        let (fake, manager, screen, ids) = (tiles.fake, tiles.manager, tiles.screen, tiles.ids)
        manager.learnMinimum(ids[1], CGSize(width: 700, height: 100))
        await tiles.settle()

        try await drag(ids[0], to: CGRect(x: 0, y: 0, width: 1200, height: 900), in: tiles)
        #expect(ratios(manager.dwindle(on: screen)).first == 0.5625)
        #expect(fake.frame(of: ids[1]).width == 700)

        try await drag(ids[0], to: CGRect(x: 0, y: 0, width: 50, height: 900), in: tiles)
        #expect(ratios(manager.dwindle(on: screen)).first == 0.1)
        #expect(fake.frame(of: ids[0]).width == 160)
    }

    @Test func theSplitHandleMovesAndSwapsTheRootSplit() async throws {
        let tiles = try await threeTiles()
        let (fake, manager, screen, ids) = (tiles.fake, tiles.manager, tiles.screen, tiles.ids)
        let divider = try #require(manager.splitDivider(on: screen))
        #expect(divider.vertical && divider.position == 800)

        manager.beginDividerDrag(on: screen)
        manager.moveDivider(on: screen, to: 1000)
        manager.endDividerDrag()
        #expect(await fake.settle(manager))
        #expect(ratios(manager.dwindle(on: screen)) == [0.625, 0.5])
        #expect(fake.frame(of: ids[1]) == CGRect(x: 1000, y: 0, width: 600, height: 450))
        #expect(manager.splitDivider(on: screen)?.position == 1000)

        manager.swapSides(on: screen)
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: ids[0]) == CGRect(x: 600, y: 0, width: 1000, height: 900))
        #expect(fake.frame(of: ids[1]) == CGRect(x: 0, y: 0, width: 600, height: 450))
        #expect(manager.splitDivider(on: screen)?.position == 600)
    }

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
}
