import AppKit
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct MoreDispatchersTests {
    private let visible = CGRect(x: 10, y: 40, width: 1400, height: 850)

    private func focus(_ id: CGWindowID, in fake: FakeBackend, manager: WindowManager) async throws {
        fake.userFocuses(id)
        manager.handle(kAXFocusedWindowChangedNotification, try #require(fake.element(id)))
        #expect(await fake.wait(manager) { manager.focusRequests.reportedFocus?.id == id })
    }

    private struct World {
        let fake: FakeBackend
        let manager: WindowManager
        let ids: [CGWindowID]
        var screens: [Screen] = []
    }

    private func world(windows count: Int, layout: Layout = .tall) async -> World {
        let fake = FakeBackend()
        fake.addScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visible: visible)
        let manager = fake.makeManager { $0.layouts = [layout, .column] }
        let ids = (0..<count).map { _ in fake.addWindow() }
        #expect(await fake.settle(manager))
        return World(fake: fake, manager: manager, ids: ids)
    }

    @Test func measuresReadPointsPercentAndChanges() throws {
        let (width, height) = try #require(Measure.pair("+50 -20"))
        #expect(width.resolve(from: 400, of: 1000) == 450 && height.resolve(from: 300, of: 1000) == 280)
        let (half, full) = try #require(Measure.pair("50% 100%"))
        #expect(half.resolve(from: 400, of: 1000) == 500 && full.resolve(from: 300, of: 800) == 800)
        let (grow, same) = try #require(Measure.pair("+10% 0"))
        #expect(grow.resolve(from: 400, of: 1000) == 500 && same.resolve(from: 300, of: 800) == 300)
        let (exactW, exactH) = try #require(Measure.pair("exact 500 300"))
        #expect(exactW.resolve(from: 1, of: 1) == 500 && exactH.resolve(from: 1, of: 1) == 300)
        for bad in ["", "50", "500 300", "exact 500", "+5 x", "+5 +5 +5", "exact +5 +5 +5", "nan% 1%"] {
            #expect(Measure.pair(bad) == nil, "\(bad)")
        }
    }

    @Test func floatingWindowResizesAndMovesByChangeAndPercent() async throws {
        let setup = await world(windows: 2)
        let (fake, manager, ids) = (setup.fake, setup.manager, setup.ids)
        try await focus(ids[0], in: fake, manager: manager)
        manager.dispatch("setfloating", "")
        #expect(await fake.settle(manager))
        manager.dispatch("resizeactive", "exact 400 300")
        manager.dispatch("moveactive", "exact 100 50")
        #expect(await fake.settle(manager))
        manager.dispatch("resizeactive", "+50 -20")
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: ids[0]) == CGRect(x: visible.minX + 100, y: visible.minY + 50, width: 450, height: 280))
        manager.dispatch("moveactive", "-30 +10")
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: ids[0]).origin == CGPoint(x: visible.minX + 70, y: visible.minY + 60))
        manager.dispatch("resizeactive", "50% 100%")
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: ids[0]).size == CGSize(width: 700, height: 850))
        manager.dispatch("moveactive", "10% 0%")
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: ids[0]).origin == CGPoint(x: visible.minX + 140, y: visible.minY))
    }

    @Test func tiledWindowResizeMovesTheSplit() async throws {
        let setup = await world(windows: 3)
        let (fake, manager, ids) = (setup.fake, setup.manager, setup.ids)
        let screen = try #require(fake.screens().first)
        let tiled = manager.tiled(on: screen)
        try await focus(tiled[0], in: fake, manager: manager)
        manager.dispatch("resizeactive", "+10% 0")
        #expect(await fake.settle(manager))
        #expect(abs(manager.state(for: screen).ratio - 0.6) < 0.001)
        try await focus(tiled[1], in: fake, manager: manager)
        manager.dispatch("resizeactive", "+10% 0")
        #expect(await fake.settle(manager))
        #expect(abs(manager.state(for: screen).ratio - 0.5) < 0.001)
        let before = ids.map(fake.frame(of:))
        for refused in ["0 +10%", "50% 50%", "exact 500 300"] {
            manager.dispatch("resizeactive", refused)
            #expect(await fake.settle(manager))
            #expect(ids.map(fake.frame(of:)) == before, "\(refused)")
        }
        manager.dispatch("moveactive", "+50 +50")
        #expect(await fake.settle(manager))
        #expect(ids.map(fake.frame(of:)) == before)
    }

    @Test func balanceSharesTheAreaEvenly() async throws {
        let setup = await world(windows: 3)
        let (fake, manager, ids) = (setup.fake, setup.manager, setup.ids)
        let screen = try #require(fake.screens().first)
        try await focus(ids[0], in: fake, manager: manager)
        manager.dispatch("splitratio", "exact 0.7")
        #expect(await fake.settle(manager))
        manager.dispatch("balance", "")
        #expect(await fake.settle(manager))
        #expect(abs(manager.state(for: screen).ratio - 1.0 / 3) < 0.001)
        let areas = ids.map { fake.frame(of: $0) }.map { $0.width * $0.height }
        #expect(areas.allSatisfy { abs($0 - areas[0]) < areas[0] * 0.01 })
    }

    @Test func balanceDoesNothingWithoutAnUnevenSplit() async {
        let setup = await world(windows: 3, layout: .column)
        let (fake, manager, ids) = (setup.fake, setup.manager, setup.ids)
        let before = ids.map(fake.frame(of:))
        manager.dispatch("balance", "")
        #expect(await fake.settle(manager))
        #expect(ids.map(fake.frame(of:)) == before)
    }

    @Test func toggleSplitFlipsTheSplitDirection() async throws {
        let setup = await world(windows: 2)
        let (fake, manager, ids) = (setup.fake, setup.manager, setup.ids)
        let screen = try #require(fake.screens().first)
        try await focus(ids[0], in: fake, manager: manager)
        manager.dispatch("togglesplit", "")
        #expect(manager.state(for: screen).layout == .wide)
        manager.dispatch("togglesplit", "")
        #expect(manager.state(for: screen).layout == .tall)
        manager.dispatch("setlayout", "column")
        manager.dispatch("togglesplit", "")
        #expect(manager.state(for: screen).layout == .row)
        manager.dispatch("setlayout", "bsp")
        manager.dispatch("togglesplit", "")
        #expect(manager.state(for: screen).layout == .bsp)
    }

    @Test func unminimizeBringsBackTheLastMinimizedWindow() async throws {
        let setup = await world(windows: 3)
        let (fake, manager, ids) = (setup.fake, setup.manager, setup.ids)
        try await focus(ids[1], in: fake, manager: manager)
        fake.minimize(ids[1])
        fake.minimize(ids[2])
        manager.scheduleRefresh(after: 0)
        #expect(await fake.settle(manager))
        #expect(manager.windows[ids[1]]?.minimized == true && manager.windows[ids[2]]?.minimized == true)
        manager.dispatch("unminimize", "")
        #expect(await fake.wait(manager) { fake.isMinimized(ids[1]) != fake.isMinimized(ids[2]) })
        #expect(!fake.isMinimized(ids[1]))
        #expect(fake.isMinimized(ids[2]))
    }

    @Test func unminimizeWithNothingMinimizedDoesNothing() async {
        let setup = await world(windows: 2)
        let (fake, manager, ids) = (setup.fake, setup.manager, setup.ids)
        fake.clearWrites()
        manager.dispatch("unminimize", "")
        #expect(await fake.settle(manager))
        #expect(fake.writes.isEmpty && !ids.contains(where: fake.isMinimized))
    }

    @Test func sendShortcutPostsToTheAppAndStaysOffTheSocket() async throws {
        let setup = await world(windows: 2)
        let (fake, manager, ids) = (setup.fake, setup.manager, setup.ids)
        try await focus(ids[0], in: fake, manager: manager)
        let pid = try #require(manager.windows[ids[0]]?.pid)
        manager.dispatch("sendshortcut", "cmd+shift t")
        let combo = CGEventFlags([.maskCommand, .maskShift]).rawValue
        #expect(fake.inputs.last == .keyToApp(17, flags: combo, pid: pid))
        manager.dispatch("sendshortcut", "ctrl tab test.fake.app")
        #expect(fake.inputs.last == .keyToApp(48, flags: CGEventFlags.maskControl.rawValue, pid: pid))
        let count = fake.inputs.count
        for bad in ["", "cmd", "cmd nokey", "cmd mouse_up", "cmd t missing.app", "bogus t", "cmd t a b"] {
            manager.dispatch("sendshortcut", bad)
        }
        #expect(fake.inputs.count == count)
        #expect(CommandRegistry.command(named: "sendshortcut")?.access == .keybindOnly)
        #expect(WindowScope.refusedCommands.contains("sendshortcut"))
    }

    private func twoDisplays() async -> World {
        let fake = FakeBackend()
        let left = fake.addScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let right = fake.addScreen(frame: CGRect(x: 1000, y: 0, width: 1000, height: 800))
        let manager = fake.makeManager { $0.layouts = [.tall] }
        let ids = [
            fake.addWindow(frame: CGRect(x: 100, y: 100, width: 600, height: 500)),
            fake.addWindow(frame: CGRect(x: 200, y: 200, width: 600, height: 500)),
            fake.addWindow(frame: CGRect(x: 1100, y: 100, width: 600, height: 500))
        ]
        #expect(await fake.settle(manager))
        return World(fake: fake, manager: manager, ids: ids, screens: [left, right])
    }

    @Test func aTargetedTiledResizeMovesTheSplitOfItsOwnDisplay() async throws {
        let setup = await twoDisplays()
        let (fake, manager, ids, screens) = (setup.fake, setup.manager, setup.ids, setup.screens)
        try await focus(ids[2], in: fake, manager: manager)
        let main = try #require(manager.tiled(on: screens[0]).first)
        manager.dispatch("resizeactive", "@id:\(main) +10% 0")
        #expect(await fake.settle(manager))
        #expect(abs(manager.state(for: screens[0]).ratio - 0.6) < 0.001)
        #expect(abs(manager.state(for: screens[1]).ratio - 0.5) < 0.001)
    }

    @Test func moveWorkspaceToMonitorSendsEveryWindowOver() async throws {
        let setup = await twoDisplays()
        let (fake, manager, ids, screens) = (setup.fake, setup.manager, setup.ids, setup.screens)
        try await focus(ids[0], in: fake, manager: manager)
        #expect(manager.currentScreen()?.uuid == screens[0].uuid)
        manager.dispatch("moveworkspacetomonitor", "right")
        #expect(await fake.settle(manager))
        for id in ids { #expect(screens[1].frame.contains(fake.frame(of: id).center), "window \(id)") }
        #expect(manager.tiled(on: screens[0]).isEmpty)
        #expect(manager.tiled(on: screens[1]).count == 3)
        manager.dispatch("moveworkspacetomonitor", "right")
        #expect(await fake.settle(manager))
        #expect(manager.tiled(on: screens[1]).count == 3)
    }

    @Test func swapWorkspacesExchangesWhatTwoDisplaysShow() async throws {
        let setup = await twoDisplays()
        let (fake, manager, ids, screens) = (setup.fake, setup.manager, setup.ids, setup.screens)
        try await focus(ids[0], in: fake, manager: manager)
        manager.dispatch("swapworkspaces", "0 1")
        #expect(await fake.settle(manager))
        #expect(screens[1].frame.contains(fake.frame(of: ids[0]).center))
        #expect(screens[1].frame.contains(fake.frame(of: ids[1]).center))
        #expect(screens[0].frame.contains(fake.frame(of: ids[2]).center))
        manager.dispatch("swapworkspaces", "0 0")
        manager.dispatch("swapworkspaces", "0")
        #expect(await fake.settle(manager))
        #expect(screens[0].frame.contains(fake.frame(of: ids[2]).center))
    }
}
