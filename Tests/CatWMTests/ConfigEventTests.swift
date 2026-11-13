@testable import CatWMKit
import Foundation
import Testing

@Suite struct ConfigEventTests {
    private func call(_ engine: ConfigEngine, _ function: Int, state: JSON = .null) async -> ConfigEngine.FunctionRun {
        let window = ConfigEngine.WindowSnapshot(title: "Notes", app: "com.apple.Notes", pid: 42, frame: .zero)
        return await withCheckedContinuation { continuation in
            engine.call(function: function, window: window, state: state) { continuation.resume(returning: $0) }
        }
    }

    @Test func anEventHandlerGetsTheEventAndTheState() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.on(\"window.added\", (e) => {",
            "  const win = catwm.state.windows.find((item) => item.id === e.window)",
            "  if (win && win.app === e.app && catwm.state.displays.length === 1) catwm.dispatch(\"setfloating\")",
            "  catwm.dispatch(\"workspace\", \"2\")",
            "  catwm.dispatch(\"resizeactive\", \"exact\", 600, 500)",
            "})"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        let loaded = engine.run()
        let event = JSON.object(["window": .int(7), "app": .string("a"), "title": .string("t")])
        let world = JSON.object([
            "windows": .array([.object(["id": .int(7), "app": .string("a")])]),
            "displays": .array([.object(["id": .string("d")])])
        ])

        let result = await withCheckedContinuation { continuation in
            engine.call(function: 0, window: nil, event: event, state: world) { continuation.resume(returning: $0) }
        }

        #expect(loaded.value?["eventHandlers"] == [["event": "window.added", "function": 0]])
        #expect(result.failure == nil)
        #expect(result.actions == [
            RuleAction(dispatcher: "setfloating", arg: ""),
            RuleAction(dispatcher: "workspace", arg: "2"),
            RuleAction(dispatcher: "resizeactive", arg: "exact 600 500")
        ])
    }

    @Test func aBindFunctionCanDispatchAndReadTheState() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => {",
            "  if (catwm.state.windows.length === 0) catwm.dispatch(\"sort\")",
            "})"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        _ = engine.run()

        let result = await call(engine, 0, state: .object(["windows": .array([])]))

        #expect(result.failure == nil)
        #expect(result.actions == [RuleAction(dispatcher: "sort", arg: "")])
    }

    @Test func anEventHandlerCantReadTheFocusedWindowOrRunAtTheTopLevel() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.on(\"focus.changed\", () => { catwm.window.focused.float() })"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        _ = engine.run()
        let result = await withCheckedContinuation { continuation in
            engine.call(function: 0, window: nil, event: .object([:])) { continuation.resume(returning: $0) }
        }
        let top = try ConfigFolder(["catwm.config.ts": catwmConfig("catwm.dispatch(\"sort\")")])
        defer { top.remove() }

        #expect(result.failure != nil)
        #expect(ConfigEngine(entry: top.entry).run().failures.isEmpty == false)
    }

    @Test func anUnknownEventIsAConfigError() {
        var config = Config()
        let value = JSON.object(["eventHandlers": [["event": "window.opened", "function": 0]]])

        let failures = ConfigScript.read(value, into: &config, file: nil)

        #expect(failures.first?.message.contains("window.opened") == true)
        #expect(config.eventHandlers.isEmpty)
    }
}
