import AppKit
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct WindowEventTests {
    private let app = "test.event.app"

    private struct World {
        let fake: FakeBackend
        let manager: WindowManager
        let folder: ConfigFolder
        let store: ConfigStore
    }

    private func script(_ lines: [String]) -> String {
        catwmConfig((["catwm.workspaces.virtual = false", "catwm.motion.enabled = false",
                      "catwm.focus.mouseFollowsFocus = false", "catwm.focus.followsMouse = false",
                      "catwm.gaps.enabled = false", "catwm.padding = 0"] + lines).joined(separator: "\n"))
    }

    private func makeWorld(_ lines: String...) throws -> World {
        let fake = FakeBackend()
        fake.addScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                       visible: CGRect(x: 10, y: 40, width: 1400, height: 850))
        let folder = try ConfigFolder(["catwm.config.ts": script(lines)])
        let defaults = try #require(UserDefaults(suiteName: "catwm-events-" + UUID().uuidString))
        let store = ConfigStore(folder: folder.url, defaults: defaults)
        let config = store.load()
        #expect(store.failures.isEmpty)
        let manager = fake.makeManager { $0 = config }
        manager.store = store
        return World(fake: fake, manager: manager, folder: folder, store: store)
    }

    private func save(_ world: World, _ lines: String...) throws {
        try world.folder.write("catwm.config.ts", script(lines))
        world.manager.reload()
        #expect(world.store.failures.isEmpty)
    }

    private func emitAdded(_ id: CGWindowID) {
        EventBus.shared.emit("window.added", ["window": .int(Int(id)), "app": .string(app), "title": .null])
    }

    @Test func aHandlerActsOnTheEventsWindowNotTheFocusedOne() async throws {
        let world = try makeWorld()
        let focused = world.fake.addWindow(pid: -101, bundleID: "test.other.app")
        let id = world.fake.addWindow(bundleID: app)
        #expect(await world.fake.settle(world.manager))
        world.fake.userFocuses(focused)
        world.manager.handle(kAXFocusedWindowChangedNotification, try #require(world.fake.element(focused)))
        #expect(await world.fake.wait(world.manager) { world.manager.focusRequests.reportedFocus?.id == focused })
        defer { try? save(world) }

        try save(world, "catwm.on(\"window.added\", (e) => {",
                 "  const win = catwm.state.windows.find((item) => item.id === e.window)",
                 "  if (win && win.app === \"\(app)\") catwm.dispatch(\"setfloating\")",
                 "})")
        emitAdded(id)
        #expect(await world.fake.wait(world.manager) { world.manager.windows[id]?.isFloating == true })

        #expect(try #require(world.manager.windows[focused]).isFloating == false)
    }

    @Test func eventsCostNothingWithoutAHandler() throws {
        let world = try makeWorld()
        #expect(world.manager.eventHandlerToken == nil)

        try save(world, "catwm.on(\"mode.changed\", () => {})")
        #expect(world.manager.eventHandlerToken != nil)
        #expect(EventBus.shared.hasSubscribers)

        try save(world)
        #expect(world.manager.eventHandlerToken == nil)
    }

    @Test func aSaveThatChangesHandlersApplies() throws {
        let world = try makeWorld("catwm.on(\"mode.changed\", () => {})")
        let before = world.manager.config
        defer { try? save(world) }

        try save(world, "catwm.on(\"tiling.changed\", () => {})")

        #expect(world.manager.config.changes(from: before) == ["eventHandlers"])
    }

    @Test func aHandlerOfAnotherEventDoesNotRun() async throws {
        let world = try makeWorld()
        let id = world.fake.addWindow(bundleID: app)
        #expect(await world.fake.settle(world.manager))
        defer { try? save(world) }
        try save(world, "catwm.on(\"display.removed\", () => { catwm.dispatch(\"setfloating\") })")

        emitAdded(id)
        await withCheckedContinuation { done in
            world.store.call(function: 0, window: nil) { _ in done.resume() }
        }
        #expect(await world.fake.settle(world.manager))

        #expect(try #require(world.manager.windows[id]).isFloating == false)
    }
}
