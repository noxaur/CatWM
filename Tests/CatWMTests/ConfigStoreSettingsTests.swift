@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@MainActor @Suite struct ConfigStoreSettingsTests {
    private func store(_ folder: ConfigFolder) -> ConfigStore {
        let suite = "catwm.test." + UUID().uuidString
        return ConfigStore(folder: folder.url, defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    private func text(_ folder: ConfigFolder) throws -> String {
        try String(contentsOf: folder.entry, encoding: .utf8)
    }

    @Test func aSettingsSaveReplacesTheLiteralInPlace() throws {
        let source = catwmConfig("// how far apart", "catwm.gaps.size = 8 // tight", "catwm.motion.enabled = true")
        let folder = try ConfigFolder(["catwm.config.ts": source])
        defer { folder.remove() }
        let store = store(folder)
        #expect(store.load().windowMarginSize == 8)

        try store.set(option: ConfigOption.at(\Config.windowMarginSize), "12")

        #expect(try text(folder) == source.replacingOccurrences(of: "size = 8", with: "size = 12"))
        #expect(store.reload().windowMarginSize == 12)
        #expect(store.failures.isEmpty)
    }

    @Test func aSettingsSaveReplacesAFieldOfAGroupObject() throws {
        let source = catwmConfig("catwm.gaps = {", "  enabled: true,", "  size: 8,", "  smart: false,", "}")
        let folder = try ConfigFolder(["catwm.config.ts": source])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()

        try store.set(option: ConfigOption.at(\Config.windowMarginSize), "12")

        #expect(try text(folder) == source.replacingOccurrences(of: "size: 8", with: "size: 12"))
        #expect(store.reload().windowMarginSize == 12)
    }

    @Test func aSettingsSaveEditsTheFileThatWroteTheOption() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": catwmConfig("import \"./gaps\"", "catwm.motion.enabled = false"),
            "gaps.ts": catwmConfig("catwm.gaps.size = 8")
        ])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()

        try store.set(option: ConfigOption.at(\Config.windowMarginSize), "12")

        #expect(try String(contentsOf: folder.url.appendingPathComponent("gaps.ts"), encoding: .utf8)
            == catwmConfig("catwm.gaps.size = 12"))
        #expect(try text(folder) == catwmConfig("import \"./gaps\"", "catwm.motion.enabled = false"))
        #expect(store.reload().windowMarginSize == 12)
    }

    @Test func aComputedValueGoesToTheSettingsBlockAndLaterSavesUpdateIt() throws {
        let source = catwmConfig("const base = 4", "catwm.gaps.size = base * 2")
        let folder = try ConfigFolder(["catwm.config.ts": source])
        defer { folder.remove() }
        let store = store(folder)
        #expect(store.load().windowMarginSize == 8)

        try store.set(option: ConfigOption.at(\Config.windowMarginSize), "12")
        #expect(try text(folder) == source + "\n// Settings\ncatwm.gaps.size = 12\n")
        #expect(store.reload().windowMarginSize == 12)

        try store.set(option: ConfigOption.at(\Config.windowMarginSize), "14")
        #expect(try text(folder) == source + "\n// Settings\ncatwm.gaps.size = 14\n")
        #expect(store.reload().windowMarginSize == 14)
    }

    @Test func anOptionTheFileNeverWritesGoesToTheSettingsBlock() throws {
        let source = catwmConfig("catwm.gaps.size = 8")
        let folder = try ConfigFolder(["catwm.config.ts": source])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()

        try store.set(option: ConfigOption.at(\Config.animate), "false")

        #expect(try text(folder) == source + "\n// Settings\ncatwm.motion.enabled = false\n")
        #expect(!store.reload().animate)
    }

    @Test func aSaveThatDoesNotGiveTheExpectedConfigLeavesTheFileUntouched() throws {
        let source = catwmConfig("catwm.gaps.size = 8")
        let folder = try ConfigFolder(["catwm.config.ts": source])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()
        var expected = store.current
        expected.windowMarginSize = 12

        #expect(throws: ConfigError.self) {
            try store.write([.init(path: "gaps.size", value: .string("wide"))], expected: expected)
        }

        #expect(try text(folder) == source)
        #expect(store.reload().windowMarginSize == 8)
    }

    @Test func aBrokenConfigFileIsNotWrittenTo() throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig("catwm.gaps.size = 8")])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()
        let broken = catwmConfig("catwm.gaps.size = (")
        try folder.write("catwm.config.ts", broken)

        #expect(throws: ConfigError.self) {
            try store.set(option: ConfigOption.at(\Config.windowMarginSize), "12")
        }
        #expect(try text(folder) == broken)
    }

    @Test func theOldOverridesFileMovesIntoTheConfigOnce() throws {
        let source = catwmConfig("catwm.gaps.size = 8")
        let folder = try ConfigFolder(["catwm.config.ts": source])
        defer { folder.remove() }
        try folder.write(ConfigStore.overridesName, """
        { "gaps": { "size": 12 }, "motion": { "enabled": false }, "layouts": ["tall", "wide"] }
        """)
        let store = store(folder)
        _ = store.load()

        #expect(store.migrateOverrides())

        let moved = try text(folder)
        #expect(moved.contains("catwm.gaps.size = 12"))
        #expect(moved.contains("// Settings"))
        #expect(!FileManager.default.fileExists(atPath: store.overridesURL.path))
        let config = store.reload()
        #expect(config.windowMarginSize == 12 && !config.animate)
        #expect(config.layouts == [.tall, .wide])
        #expect(!store.migrateOverrides())
    }

    @Test func overriddenBindsMoveAndKeepTheBindsAFunctionOwns() throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"a\", \"sort\")",
            "catwm.bind([\"alt\"], \"f\", () => { catwm.window.focused.float() })"
        )])
        defer { folder.remove() }
        try folder.write(ConfigStore.overridesName, """
        { "binds": [{ "mods": ["alt"], "key": "b", "run": "retile" }], "gaps": { "size": 12 } }
        """)
        let store = store(folder)
        _ = store.load()

        #expect(store.migrateOverrides())

        let config = store.reload()
        #expect(config.windowMarginSize == 12)
        #expect(config.bindings.contains { $0.dispatcher == "retile" })
        #expect(config.bindings.contains { $0.function != nil })
        #expect(!FileManager.default.fileExists(atPath: store.overridesURL.path))
    }

    @Test func anOverridesFileThatCanNotMoveStaysAndSaysWhy() throws {
        let source = catwmConfig("catwm.gaps.size = 8")
        let folder = try ConfigFolder(["catwm.config.ts": source])
        defer { folder.remove() }
        try folder.write(ConfigStore.overridesName, "{ \"gaps\": { \"size\": \"wide\" } }")
        let store = store(folder)
        _ = store.load()

        #expect(!store.migrateOverrides())

        #expect(try text(folder) == source)
        #expect(FileManager.default.fileExists(atPath: store.overridesURL.path))
        #expect(store.failures.first?.phase == .migrate)
    }

    @Test func aSettingsSaveKeepsTheBindsAFunctionOwns() throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"a\", \"sort\")",
            "catwm.bind([\"alt\"], \"f\", () => { catwm.window.focused.float() })"
        )])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()
        let copy = store.settingsCopy
        var edited = copy.shown
        let index = try #require(edited.bindings.firstIndex { $0.dispatcher == "sort" })
        edited.bindings[index] = KeyBinding(keyCode: 11, mods: .maskAlternate, dispatcher: "sort", arg: "")

        try store.save(settings: edited, from: copy)

        let binds = store.reload().bindings
        #expect(binds.contains { $0.keyCode == 11 && $0.dispatcher == "sort" })
        #expect(binds.contains { $0.function != nil })
        #expect(binds.count == 2)
    }
}
