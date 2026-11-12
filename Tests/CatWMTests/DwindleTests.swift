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
        #expect(tree.frames(in: rect, minimums: [CGSize(width: 600, height: 0), CGSize(width: 600, height: 0)]) == [
            CGRect(x: 0, y: 0, width: 1000, height: 450), CGRect(x: 0, y: 450, width: 1000, height: 450)
        ])
        #expect(tree.frames(in: rect, minimums: [CGSize(width: 700, height: 0), .zero])[0].width == 700)
        #expect(tree.frames(in: rect, minimums: [CGSize(width: 900, height: 600), CGSize(width: 900, height: 600)])
            == tree.frames(in: rect))
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
}
