import Foundation

@MainActor package final class PluginDispatchers {
    private struct Entry {
        let owner: ObjectIdentifier
        let run: @MainActor (CatWMEngine.PluginCall) -> Void
    }

    private var entries: [String: Entry] = [:]
    private let hostToken: ObjectIdentifier

    package init() { hostToken = ObjectIdentifier(Self.self) }

    package nonisolated static let maxLength = 64

    package nonisolated static func isNamespaced(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return name.utf8.count <= maxLength && parts.count >= 2 && parts.allSatisfy { part in
            guard let first = part.unicodeScalars.first, first != "-", first != "_" else { return false }
            return part.unicodeScalars.allSatisfy { scalar in
                ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-" || scalar == "_"
            }
        }
    }

    package func isRegistered(_ name: String) -> Bool { entries[name.lowercased()] != nil }

    package func register(_ rawName: String, for client: ControlConnection) throws -> String {
        let name = try claim(rawName, owner: ObjectIdentifier(client))
        entries[name] = Entry(owner: ObjectIdentifier(client)) { [weak client] call in
            let message = JSON.object(["invoke": .string(call.name),
                                       "data": ["arg": .string(call.arg), "window": call.window]])
            client?.send(message.encoded() + Data("\n".utf8))
        }
        return name
    }

    package func register(_ rawName: String, handler: @escaping @MainActor (CatWMEngine.PluginCall) -> Void) throws {
        let name = try claim(rawName, owner: hostToken)
        entries[name] = Entry(owner: hostToken, run: handler)
    }

    package func unregister(_ rawName: String, for client: ControlConnection) throws {
        let name = rawName.lowercased()
        guard entries[name]?.owner == ObjectIdentifier(client) else {
            throw ControlError.failed("`\(name)` is not registered by this connection")
        }
        entries[name] = nil
    }

    package func unregisterHost(_ rawName: String) {
        let name = rawName.lowercased()
        if entries[name]?.owner == hostToken { entries[name] = nil }
    }

    package func remove(_ client: ControlConnection) {
        let owner = ObjectIdentifier(client)
        entries = entries.filter { $0.value.owner != owner }
    }

    package func invoke(_ rawName: String, arg: String, window: Window?) -> Bool {
        let name = rawName.lowercased()
        guard let entry = entries[name] else { return false }
        let target: JSON = window.map {
            ["id": .int(Int($0.id)), "app": $0.bundleID.map(JSON.string) ?? .null,
             "title": $0.title.map(JSON.string) ?? .null]
        } ?? .null
        entry.run(CatWMEngine.PluginCall(name: name, arg: arg, window: target))
        return true
    }

    private func claim(_ rawName: String, owner: ObjectIdentifier) throws -> String {
        let name = rawName.lowercased()
        guard Self.isNamespaced(name) else {
            throw ControlError.invalid("`\(rawName)` is not a namespaced name: use `app.name` with a-z, 0-9, - and _")
        }
        guard !CommandRegistry.dispatcherNames.contains(name), CommandRegistry.command(named: name) == nil else {
            throw ControlError.failed("`\(name)` is a built-in name")
        }
        if let taken = entries[name], taken.owner != owner {
            throw ControlError.failed("`\(name)` is registered by another connection")
        }
        return name
    }
}
