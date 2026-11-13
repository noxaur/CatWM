import AppKit
import CatWMFakes
@testable import CatWMKit
import Foundation
import Testing

@Suite struct TextPatternTests {
    @Test func aListTakesExactTrailingStarAndRegexEntries() {
        let entries = ["com.apple.calculator", "com.adobe.*", "/^org\\.mozilla\\.(firefox|nightly)$/", "/slack/i"]
        #expect(TextPattern.lists("com.apple.calculator", in: entries))
        #expect(TextPattern.lists("com.adobe.Photoshop", in: entries))
        #expect(TextPattern.lists("org.mozilla.nightly", in: entries))
        #expect(TextPattern.lists("com.tinyspeck.SLACK", in: entries))
        #expect(!TextPattern.lists("org.mozilla.firefoxdev", in: entries))
        #expect(!TextPattern.lists("com.apple.calculatorx", in: entries))
    }

    @Test func aBrokenRegexEntryMatchesNothingInsteadOfCrashing() {
        #expect(!TextPattern.lists("a", in: ["/[^]/"]))
        #expect(throws: TextPattern.Failure.self) { try TextPattern.regex(written: "/[^]/") }
        #expect(throws: TextPattern.Failure.self) { try TextPattern.regex(written: "/a/z") }
        #expect(TextPattern.split("not a regex") == nil)
    }

    @Test func everyTextFieldOfARuleTakesARegExp() throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig("""
        catwm.windows({ app: /^com\\.apple\\./, title: /doc/i, workspace: /^[12]$/, display: /^Built/ },
                      (win) => win.float())
        catwm.workspaces({ app: /safari/i, name: /^w/, display: /ext/ }, () => { catwm.gaps.size = 1 })
        catwm.floating.apps = ["com.a.*", /^org\\./]
        """)])
        defer { folder.remove() }
        let run = ConfigEngine(entry: folder.entry).run()
        var config = Config()
        let diagnostics = ConfigScript.read(try #require(run.value), into: &config, file: folder.entry.path)

        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.message))")
        let window = try #require(config.windowRules.first)
        let facts: Facts = [.app: .string("com.apple.Safari"), .title: .string("My DOC"),
                            .workspace: .array([.string("1")]), .display: .array([.string("Builtin")])]
        #expect(window.when.holds(facts))
        #expect(!window.when.holds(facts.merging([.app: .string("org.x")]) { $1 }))
        #expect(!window.when.holds(facts.merging([.workspace: .array([.string("3")])]) { $1 }))
        let workspace = try #require(config.workspaceRules.first)
        let workspaceFacts: Facts = [.apps: .array([.string("com.apple.Safari")]), .name: .array([.string("web")]),
                                     .display: .array([.string("external")])]
        #expect(workspace.when.holds(workspaceFacts))
        #expect(!workspace.when.holds(workspaceFacts.merging([.name: .array([.string("code")])]) { $1 }))
        #expect(config.floating == ["com.a.*", "/^org\\./"])
        #expect(Config.lists("org.mozilla", in: config.floating))
    }

    @Test func aRegExpWithACommaInAListIsRefused() throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig("catwm.floating.apps = [/a{1,2}/]")])
        defer { folder.remove() }
        let run = ConfigEngine(entry: folder.entry).run()
        var config = Config()
        let diagnostics = ConfigScript.read(try #require(run.value), into: &config, file: folder.entry.path)
        #expect(diagnostics.first?.message.contains("holds a comma") == true)
    }
}

@Suite struct WindowTargetParserTests {
    private func holds(_ text: String, _ facts: Facts) throws -> Bool {
        try WindowTarget(text).condition.holds(facts)
    }

    @Test func eachFieldMatches() throws {
        let facts: Facts = [.app: .string("com.apple.Safari"), .title: .string("Inbox (3)"), .id: .int(42),
                            .pid: .int(7), .workspace: .array([.string("2"), .string("web")]),
                            .display: .array([.string("builtin")])]
        #expect(try holds("app:com.apple.Safari", facts))
        #expect(try holds("app:com.apple.*", facts))
        #expect(try holds("app:/safari$/i", facts))
        #expect(try holds("title:/^Inbox/", facts))
        #expect(try holds("title:\"Inbox (3)\"", facts))
        #expect(try holds("id:42", facts))
        #expect(try holds("address:42", facts))
        #expect(try holds("@pid:7", facts))
        #expect(try holds("workspace:web", facts))
        #expect(try holds("display:/built/", facts))
        #expect(try !holds("id:43", facts))
        #expect(try !holds("title:/^Outbox/", facts))
    }

    @Test func badTargetsSayWhy() {
        #expect(throws: WindowTarget.Failure.self) { try WindowTarget("nothing") }
        #expect(throws: WindowTarget.Failure.self) { try WindowTarget("colour:red") }
        #expect(throws: WindowTarget.Failure.self) { try WindowTarget("id:abc") }
        #expect(throws: WindowTarget.Failure.self) { try WindowTarget("title:") }
        #expect(throws: WindowTarget.Failure.self) { try WindowTarget("title:/[^]/") }
    }

    @Test func aLeadingTargetIsSplitFromTheRest() throws {
        let plain = try #require(try WindowTarget.leading(in: "@app:com.a.b exact 600 500"))
        #expect(plain.rest == "exact 600 500")
        #expect(plain.target == (try WindowTarget("app:com.a.b")))
        let quoted = try #require(try WindowTarget.leading(in: "@title:\"My Doc\" 3"))
        #expect(quoted.rest == "3")
        let regex = try #require(try WindowTarget.leading(in: "@title:/a b\\/c/i l"))
        #expect(regex.rest == "l")
        #expect(regex.target == (try WindowTarget("title:/a b\\/c/i")))
        #expect(try WindowTarget.leading(in: "exact 1 2") == nil)
        #expect(try #require(try WindowTarget.leading(in: "@id:5")).rest.isEmpty)
    }
}

@Suite(.timeLimit(.minutes(1))) @MainActor struct WindowTargetDispatchTests {
    private let visible = CGRect(x: 10, y: 40, width: 1400, height: 850)

    private func makeWorld() -> (fake: FakeBackend, manager: WindowManager) {
        let fake = FakeBackend()
        fake.addScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visible: visible)
        let manager = fake.makeManager { config in
            config = .parse("virtual-workspaces = false\nanimation = false\ngaps = false")
        }
        return (fake, manager)
    }

    private func focus(_ id: CGWindowID, _ world: (fake: FakeBackend, manager: WindowManager)) async throws {
        world.fake.userFocuses(id)
        world.manager.handle(kAXFocusedWindowChangedNotification, try #require(world.fake.element(id)))
        #expect(await world.fake.wait(world.manager) { world.manager.focusRequests.reportedFocus?.id == id })
    }

    @Test func aPluginDispatcherGetsTheTargetAndTheRestOfTheArgument() async throws {
        let world = makeWorld()
        let mail = world.fake.addWindow(bundleID: "test.mail", title: "Inbox")
        let notes = world.fake.addWindow(pid: -101, bundleID: "test.notes", title: "Todo")
        #expect(await world.fake.settle(world.manager))
        try await focus(notes, world)
        let peer = PluginDispatcherTests.Peer()
        _ = try world.manager.plugins.register("myapp.look", for: peer.client)

        world.manager.dispatch("myapp.look", "@app:test.mail left")
        let data = try #require(peer.nextLine()?["data"])
        #expect(data["arg"] == "left")
        #expect(data["window"]?["id"] == .int(Int(mail)))
    }

    @Test func aFunctionsActionsHonourATarget() async throws {
        let world = makeWorld()
        let mail = world.fake.addWindow(bundleID: "test.mail", title: "Inbox")
        let notes = world.fake.addWindow(pid: -101, bundleID: "test.notes", title: "Todo")
        #expect(await world.fake.settle(world.manager))
        try await focus(notes, world)
        let pressed = try #require(world.manager.windows[notes])

        world.manager.run(RuleAction(dispatcher: "setfloating", arg: "@app:test.mail"), on: pressed)
        #expect(await world.fake.wait(world.manager) { world.manager.windows[mail]?.isFloating == true })
        #expect(world.manager.windows[notes]?.isFloating == false)

        world.manager.run(RuleAction(dispatcher: "focuswindow", arg: "app:test.mail"), on: pressed)
        #expect(await world.fake.wait(world.manager) { world.manager.focusRequests.reportedFocus?.id == mail })
    }

    @Test func aDispatcherActsOnTheTargetInsteadOfTheFocusedWindow() async throws {
        let world = makeWorld()
        let mail = world.fake.addWindow(bundleID: "test.mail", title: "Inbox")
        let notes = world.fake.addWindow(pid: -101, bundleID: "test.notes", title: "Todo")
        #expect(await world.fake.settle(world.manager))
        try await focus(notes, world)

        world.manager.dispatch("setfloating", "@app:test.mail")
        #expect(await world.fake.wait(world.manager) { world.manager.windows[mail]?.isFloating == true })
        #expect(world.manager.windows[notes]?.isFloating == false)

        world.manager.dispatch("settiled", "@title:/^inb/i")
        #expect(await world.fake.wait(world.manager) { world.manager.windows[mail]?.isFloating == false })
    }

    @Test func aTargetThatMatchesNothingDoesNothing() async throws {
        let world = makeWorld()
        world.fake.addWindow(bundleID: "test.mail")
        let notes = world.fake.addWindow(pid: -101, bundleID: "test.notes")
        #expect(await world.fake.settle(world.manager))
        try await focus(notes, world)

        world.manager.dispatch("setfloating", "@app:test.missing")
        world.manager.dispatch("setfloating", "@bogus")
        world.manager.dispatch("movefocus", "@app:test.mail")

        #expect(world.manager.windows[notes]?.isFloating == false)
    }

    @Test func focuswindowFocusesTheMatchAndFocuslastGoesBack() async throws {
        let world = makeWorld()
        let first = world.fake.addWindow(bundleID: "test.one")
        let second = world.fake.addWindow(pid: -101, bundleID: "test.two")
        let third = world.fake.addWindow(pid: -102, bundleID: "test.three")
        #expect(await world.fake.settle(world.manager))
        try await focus(first, world)
        try await focus(second, world)

        world.manager.dispatch("focuswindow", "app:test.three")
        #expect(await world.fake.wait(world.manager) { world.manager.focusedWindow()?.id == third })

        world.manager.dispatch("focuslast", "")
        #expect(await world.fake.wait(world.manager) { world.manager.focusedWindow()?.id == second })

        world.manager.dispatch("focuslast", "")
        #expect(await world.fake.wait(world.manager) { world.manager.focusedWindow()?.id == third })

        world.manager.dispatch("focuswindow", "id:\(first)")
        #expect(await world.fake.wait(world.manager) { world.manager.focusedWindow()?.id == first })
    }
}
