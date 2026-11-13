import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct ScratchpadPinTests {
    private func focus(_ id: CGWindowID, in fake: FakeBackend, manager: WindowManager) async throws {
        fake.userFocuses(id)
        manager.handle(kAXFocusedWindowChangedNotification, try #require(fake.element(id)))
        #expect(await fake.wait(manager) { manager.focusRequests.reportedFocus?.id == id })
    }

    @Test func entriesKeepTheOrderTheWindowsWereHidden() {
        var pads = Scratchpads()
        pads.stash(1, as: "a")
        pads.stash(2, as: "a")
        pads.stash(3, as: "b")
        #expect(pads.lastHidden(named: "a") == 2)
        pads.reveal(2)
        #expect(pads.lastHidden(named: "a") == 1)
        #expect(pads.shown(named: "a") == [2])
        pads.hide(2)
        #expect(pads.lastHidden(named: "a") == 2)
        pads.stash(1, as: "b")
        #expect(pads.name(of: 1) == "b" && pads.hiddenIDs == [1, 2, 3])
        pads.forget(2)
        #expect(pads.lastHidden(named: "a") == nil)
        #expect(Scratchpads.name("  ") == Scratchpads.defaultName)
    }

    @Test func aRefusedFollowMoveWaitsBeforeItRetries() {
        var pins = PinnedWindows()
        let now = Date()
        let first = pins.claimFollow(7, now: now)
        let early = pins.claimFollow(7, now: now.addingTimeInterval(0.5))
        let late = pins.claimFollow(7, now: now.addingTimeInterval(1.5))
        #expect(first && !early && late)
    }

    @Test func hidingTakesTheWindowOutOfTheTilingAndTogglingShowsItCentered() async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager { $0.layouts = [.tall] }
        let first = fake.addWindow()
        let second = fake.addWindow()
        #expect(await fake.settle(manager))
        try await focus(second, in: fake, manager: manager)

        manager.dispatch("movetoscratchpad", "")
        #expect(await fake.settle(manager))
        #expect(manager.scratchpads.isHidden(second))
        #expect(manager.isParked(fake.frame(of: second), [screen]))
        #expect(!manager.visible.contains(second))
        #expect(manager.tiled(on: screen) == [first])
        #expect(fake.frame(of: first) == screen.visible)
        #expect(manager.focusedWindow()?.id == first)

        manager.dispatch("togglescratchpad", "")
        #expect(await fake.settle(manager))
        let area = screen.visible
        let size = CGSize(width: area.width * 0.8, height: area.height * 0.8)
        #expect(fake.frame(of: second) == CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                                  width: size.width, height: size.height).pixelAligned)
        #expect(manager.visible.contains(second) && manager.windows[second]?.isFloating == true)
        #expect(manager.tiled(on: screen) == [first])
        #expect(manager.focusedWindow()?.id == second)

        manager.dispatch("togglescratchpad", "")
        #expect(await fake.settle(manager))
        #expect(manager.isParked(fake.frame(of: second), [screen]))
        #expect(manager.focusedWindow()?.id == first)
    }

    @Test func eachNameKeepsItsOwnWindowAndTheSizeOptionApplies() async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager { $0.scratchpadSize = 50 }
        let notes = fake.addWindow()
        let terminal = fake.addWindow()
        #expect(await fake.settle(manager))
        try await focus(notes, in: fake, manager: manager)
        manager.dispatch("movetoscratchpad", "notes")
        #expect(await fake.settle(manager))
        try await focus(terminal, in: fake, manager: manager)
        manager.dispatch("movetoscratchpad", "term")
        #expect(await fake.settle(manager))

        manager.dispatch("togglescratchpad", "notes")
        #expect(await fake.settle(manager))
        let half = CGSize(width: screen.visible.width / 2, height: screen.visible.height / 2)
        #expect(fake.frame(of: notes).size == half)
        #expect(manager.isParked(fake.frame(of: terminal), [screen]))
        #expect(manager.scratchpads.name(of: terminal) == "term")
    }

    @Test func aClosedScratchpadWindowLeavesNoEntry() async throws {
        let fake = FakeBackend()
        _ = fake.addScreen()
        let manager = fake.makeManager()
        let id = fake.addWindow()
        _ = fake.addWindow()
        #expect(await fake.settle(manager))
        try await focus(id, in: fake, manager: manager)
        manager.dispatch("movetoscratchpad", "")
        #expect(await fake.settle(manager))
        fake.close(id)
        #expect(await fake.settle(manager))
        #expect(manager.scratchpads.entries.isEmpty)
    }

    @Test func pinFloatsTheWindowAndToggles() async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager { $0.layouts = [.tall] }
        let first = fake.addWindow()
        let second = fake.addWindow()
        #expect(await fake.settle(manager))
        try await focus(second, in: fake, manager: manager)

        manager.dispatch("pin", "")
        #expect(await fake.settle(manager))
        #expect(manager.pins.contains(second) && manager.windows[second]?.isFloating == true)
        #expect(manager.tiled(on: screen) == [first])
        let state = try #require(manager.windowsJSON().array?.first { $0["id"] == .int(Int(second)) })
        #expect(state["pinned"] == .bool(true) && state["scratchpad"] == .null)

        manager.dispatch("pin", "on")
        #expect(manager.pins.contains(second))
        manager.dispatch("pin", "")
        #expect(!manager.pins.contains(second))
    }

    @Test func pinningLeavesAScratchpadAndHidingLeavesThePin() async throws {
        let fake = FakeBackend()
        _ = fake.addScreen()
        let manager = fake.makeManager()
        let id = fake.addWindow()
        _ = fake.addWindow()
        #expect(await fake.settle(manager))
        try await focus(id, in: fake, manager: manager)
        manager.dispatch("pin", "on")
        manager.dispatch("movetoscratchpad", "")
        #expect(await fake.settle(manager))
        #expect(!manager.pins.contains(id) && manager.scratchpads.isHidden(id))
        manager.setPinned(true, try #require(manager.windows[id]))
        #expect(!manager.pins.contains(id))
    }

    @Test func aRuleRecordsPinAndScratchpad() throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.windows({ app: \"com.apple.Notes\" }, (win) => { win.pin() })",
            "catwm.windows({ app: \"com.apple.Terminal\" }, (win) => { win.scratchpad(\"term\") })",
            "catwm.windows({ app: \"com.apple.Music\" }, (win) => { win.pin(false); win.scratchpad() })"
        )])
        defer { folder.remove() }
        let rules = try #require(ConfigEngine(entry: folder.entry).run().value?["windowRules"]?.array)
        let actions = rules.map { $0["set"]?.array?.map { $0.array ?? [$0] } }
        #expect(actions == [[[.string("pin"), .string("on")]],
                            [[.string("movetoscratchpad"), .string("term")]],
                            [[.string("pin"), .string("off")], [.string("movetoscratchpad"), .string("")]]])
    }
}
