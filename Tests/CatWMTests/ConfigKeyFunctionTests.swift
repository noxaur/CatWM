@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Suite struct ConfigKeyFunctionTests {
    private func call(_ engine: ConfigEngine, _ function: Int) async -> ConfigEngine.FunctionRun {
        let window = ConfigEngine.WindowSnapshot(title: "Notes", app: "com.apple.Notes", pid: 42,
                                                 frame: CGRect(x: 10, y: 20, width: 300, height: 200))
        return await withCheckedContinuation { continuation in
            engine.call(function: function, window: window) { continuation.resume(returning: $0) }
        }
    }

    @Test func aKeyFunctionRecordsTheActionsOfTheFocusedWindow() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => {",
            "  const win = catwm.window.focused",
            "  if (win.app === \"com.apple.Notes\" && win.frame.width === 300) win.float()",
            "  win.resize(600, 600)",
            "  win.move(10, 20)",
            "  win.center()",
            "  win.fullscreen()",
            "  win.tile()",
            "  win.moveTo(\"3\")",
            "})",
            "catwm.bind([\"ctrl\"], \"1\", [\"workspace\", \"1\"])"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        let loaded = engine.run()

        #expect(loaded.value?["binds"]?.array?.first?["run"] == .object(["function": .int(0)]))
        #expect(loaded.value?["binds"]?.array?.last?["run"] == .array([.string("workspace"), .string("1")]))
        let result = await call(engine, 0)

        #expect(result.failure == nil)
        #expect(result.actions == [
            RuleAction(dispatcher: "setfloating", arg: ""),
            RuleAction(dispatcher: "resizeactive", arg: "exact 600 600"),
            RuleAction(dispatcher: "moveactive", arg: "exact 10 20"),
            RuleAction(dispatcher: "centerwindow", arg: ""),
            RuleAction(dispatcher: "fullscreen", arg: ""),
            RuleAction(dispatcher: "settiled", arg: ""),
            RuleAction(dispatcher: "movetoworkspacesilent", arg: "3")
        ])
    }

    @Test func aThrowRunsNoActionsAndReportsLikeAConfigError() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => {",
            "  catwm.window.focused.float()",
            "  throw new Error(\"nope\")",
            "})"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        _ = engine.run()

        let result = await call(engine, 0)

        #expect(result.actions.isEmpty)
        #expect(result.failure?.phase == .evaluate)
        #expect(result.failure?.message == "Error: nope")
        #expect(result.failure?.line == 4)
        #expect(await call(engine, 5).failure != nil)
    }

    @Test func aWriteInsideAKeyFunctionIsRefused() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => { catwm.gaps.size = 3 })"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        _ = engine.run()

        let result = await call(engine, 0)

        #expect(result.failure?.phase == .validate)
        #expect(result.failure?.message.hasPrefix("set options while the config loads") == true)
    }

    @Test(.timeLimit(.minutes(1))) func aFunctionThatNeverEndsRunsNoActions() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => { catwm.window.focused.float(); while (true) {} })"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        _ = engine.run()

        let result = await call(engine, 0)

        #expect(result.actions.isEmpty)
        #expect(result.failure?.message.hasPrefix("the key's function ran longer than 1 s") == true)
    }

    @Test func aFailedSaveKeepsTheFunctionsOfTheLastGoodConfig() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => catwm.window.focused.float())"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        _ = engine.run()
        try folder.write("catwm.config.ts", catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => catwm.window.focused.tile())", "throw new Error(\"broken\")"
        ))
        #expect(engine.run().failures.count == 1)

        #expect(await call(engine, 0).actions == [RuleAction(dispatcher: "setfloating", arg: "")])
    }
}
