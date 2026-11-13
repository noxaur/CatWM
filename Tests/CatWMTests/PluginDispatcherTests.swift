import AppKit
@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@MainActor @Suite struct PluginDispatcherTests {
    final class Peer {
        let client: ControlConnection
        private let descriptor: Int32

        init() {
            var pair: [Int32] = [0, 0]
            socketpair(AF_UNIX, SOCK_STREAM, 0, &pair)
            client = ControlConnection(descriptor: pair[0], onLine: { _, _ in }, onClose: { _ in })
            descriptor = pair[1]
            client.start()
        }

        deinit { Darwin.close(descriptor) }

        func nextLine() -> JSON? {
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 2000) > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = read(descriptor, &buffer, buffer.count)
            return count > 0 ? JSON.parse(Data(buffer[0..<count])) : nil
        }

        func silent() -> Bool {
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            return poll(&poller, 1, 150) == 0
        }
    }

    private func call(_ text: String, _ client: ControlConnection?, _ manager: WindowManager) -> JSON {
        var data = Data()
        ControlServer.respond(to: Data(text.utf8), client: client, manager: manager) { data = $0 }
        return JSON.parse(data) ?? .null
    }

    @Test func aRegisteredNameRunsThroughDispatchAndTheBind() throws {
        let manager = WindowManager(config: Config())
        let peer = Peer()
        let answer = call(#"{"id":1,"command":"register","args":{"name":"MyApp.Toggle-Notes"}}"#, peer.client, manager)
        #expect(answer["ok"] == .bool(true))
        #expect(answer["result"]?["name"] == "myapp.toggle-notes")
        let request = #"{"id":2,"command":"dispatch","args":{"dispatcher":"myapp.toggle-notes","arg":"x"}}"#
        let viaCommand = call(request, peer.client, manager)
        #expect(viaCommand["ok"] == .bool(true))
        let invoked = try #require(peer.nextLine())
        #expect(invoked["invoke"] == "myapp.toggle-notes")
        #expect(invoked["data"]?["arg"] == "x")
        #expect(invoked["data"]?["window"] == .null)
        manager.dispatch("myapp.toggle-notes", "y")
        #expect(try #require(peer.nextLine())["data"]?["arg"] == "y")
    }

    @Test func theInvocationCarriesTheTargetWindow() throws {
        let manager = WindowManager(config: Config())
        let peer = Peer()
        _ = try manager.plugins.register("myapp.look", for: peer.client)
        let window = Window(id: 7, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: "com.example.app")
        window.title = "Notes"
        #expect(manager.plugins.invoke("myapp.look", arg: "", window: window))
        let target = try #require(peer.nextLine()?["data"]?["window"])
        #expect(target == ["id": 7, "app": "com.example.app", "title": "Notes"])
    }

    @Test func unregisterStopsInvocationsAndOnlyTheOwnerCanDoIt() throws {
        let manager = WindowManager(config: Config())
        let (owner, other) = (Peer(), Peer())
        _ = try manager.plugins.register("myapp.one", for: owner.client)
        let refused = call(#"{"id":1,"command":"unregister","args":{"name":"myapp.one"}}"#, other.client, manager)
        #expect(refused["ok"] == .bool(false))
        #expect(manager.plugins.isRegistered("myapp.one"))
        let removed = call(#"{"id":2,"command":"unregister","args":{"name":"myapp.one"}}"#, owner.client, manager)
        #expect(removed["ok"] == .bool(true))
        manager.dispatch("myapp.one", "")
        #expect(owner.silent())
    }

    @Test func aClosedConnectionTakesItsNamesAway() throws {
        let manager = WindowManager(config: Config())
        let peer = Peer()
        _ = try manager.plugins.register("myapp.one", for: peer.client)
        _ = try manager.plugins.register("myapp.two", for: peer.client)
        manager.connectionClosed(peer.client)
        #expect(!manager.plugins.isRegistered("myapp.one"))
        #expect(!manager.plugins.isRegistered("myapp.two"))
        let next = Peer()
        _ = try manager.plugins.register("myapp.one", for: next.client)
    }

    @Test(arguments: ["movefocus", "workspace", "exec", "launch", "status", "agent.open", "config.get", "a.b.", ".a",
                      "my app.x", "myapp", "", "-a.b"])
    func aPluginCannotShadowABuiltInOrUseABadName(_ name: String) throws {
        let manager = WindowManager(config: Config())
        let peer = Peer()
        #expect(throws: ControlError.self) { try manager.plugins.register(name, for: peer.client) }
        #expect(!manager.plugins.isRegistered(name))
    }

    @Test func anotherConnectionCannotTakeARegisteredName() throws {
        let manager = WindowManager(config: Config())
        let (first, second) = (Peer(), Peer())
        _ = try manager.plugins.register("myapp.one", for: first.client)
        #expect(throws: ControlError.self) { try manager.plugins.register("myapp.one", for: second.client) }
        _ = try manager.plugins.register("myapp.one", for: first.client)
        manager.dispatch("myapp.one", "")
        #expect(first.nextLine() != nil)
        #expect(second.silent())
    }

    @Test func registeringNeedsAConnectionAndAPluginNeverMakesKeybindOnlyCallable() throws {
        let manager = WindowManager(config: Config())
        #expect(throws: ControlError.self) {
            try CommandRegistry.execute("register", ["name": "myapp.one"], client: nil, manager: manager)
        }
        let peer = Peer()
        _ = try manager.plugins.register("myapp.exec", for: peer.client)
        let answer = call(#"{"id":1,"command":"dispatch","args":{"dispatcher":"exec","arg":"true"}}"#,
                          peer.client, manager)
        #expect(answer["error"]?["code"] == "forbidden")
        #expect(peer.silent())
    }

    @Test func anUnregisteredNamespacedNameDoesNothing() {
        let manager = WindowManager(config: Config())
        let answer = call(#"{"id":1,"command":"dispatch","args":{"dispatcher":"myapp.nobody"}}"#, nil, manager)
        #expect(answer["ok"] == .bool(true))
        manager.dispatch("myapp.nobody", "")
        #expect(!manager.plugins.invoke("myapp.nobody", arg: "", window: nil))
        let plain = call(#"{"id":2,"command":"dispatch","args":{"dispatcher":"nobody"}}"#, nil, manager)
        #expect(plain["ok"] == .bool(false))
    }

    @Test func aScopedInstanceStillRunsPluginDispatchers() throws {
        let manager = WindowManager(config: Config(), scope: WindowScope(pids: [10]))
        let peer = Peer()
        _ = try manager.plugins.register("myapp.one", for: peer.client)
        manager.dispatch("myapp.one", "z")
        #expect(peer.nextLine()?["data"]?["arg"] == "z")
        #expect(manager.scopeRefusal("myapp.one") == nil)
        #expect(WindowScope.allowedCommands.isSuperset(of: ["register", "unregister"]))
    }

    @Test func theEmbeddedHandlerRunsAndKeepsTheSameRules() throws {
        let manager = WindowManager(config: Config())
        var calls: [CatWMEngine.PluginCall] = []
        try manager.plugins.register("host.ping") { calls.append($0) }
        manager.dispatch("host.ping", "a")
        #expect(calls == [CatWMEngine.PluginCall(name: "host.ping", arg: "a", window: .null)])
        #expect(throws: ControlError.self) { try manager.plugins.register("movefocus") { _ in } }
        let peer = Peer()
        #expect(throws: ControlError.self) { try manager.plugins.register("host.ping", for: peer.client) }
        manager.plugins.unregisterHost("host.ping")
        manager.dispatch("host.ping", "b")
        #expect(calls.count == 1)
    }

    @Test func aNamespacedNameIsAValidActionInTheConfig() {
        var config = Config()
        let value = JSON.object(["binds": .array([
            ["mods": ["alt"], "key": "n", "run": ["myapp.toggle", "arg"]],
            ["mods": ["alt"], "key": "m", "run": "myapp.other"]
        ])])
        let diagnostics = ConfigScript.read(value, into: &config, file: nil)
        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.message))")
        #expect(config.bindings.map(\.dispatcher) == ["myapp.toggle", "myapp.other"])
        #expect(config.bindings.first?.arg == "arg")
        var strict = Config()
        let unknown = ConfigScript.read(.object(["binds": .array([["mods": [], "key": "n", "run": "sortt"]])]),
                                        into: &strict, file: nil)
        #expect(unknown.map(\.message) == ["`binds[0].run` is an unknown action `sortt`"])
    }
}
