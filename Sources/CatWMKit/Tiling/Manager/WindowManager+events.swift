import AppKit

extension WindowManager {
    func syncEventHandlers() {
        let wanted = !config.eventHandlers.isEmpty
        guard wanted != (eventHandlerToken != nil) else { return }
        if wanted {
            eventHandlerToken = EventBus.shared.listen { [weak self] name, data in self?.runHandlers(for: name, data) }
        } else if let token = eventHandlerToken {
            EventBus.shared.stopListening(token)
            eventHandlerToken = nil
        }
    }

    private func runHandlers(for event: String, _ data: JSON) {
        let functions = config.eventHandlers.filter { $0.event == event }.map(\.function)
        guard !functions.isEmpty else { return }
        let id = data["window"]?.int.map { CGWindowID($0) }
        let world = scriptState()
        for function in functions {
            store.call(function: function, window: nil, event: data, state: world) { [weak self] result in
                guard let self else { return }
                if let failure = result.failure { return Log.info("config: \(failure.text)") }
                let target = id.flatMap { windows[$0] }
                if id != nil, target == nil, event != "window.removed" { return }
                for action in result.actions { run(action, on: target) }
            }
        }
    }

    func scriptState() -> JSON {
        let snapshot = snapshot()
        let windows = snapshot.windows.keys.sorted().compactMap { id -> JSON? in
            guard let entry = snapshot.windows[id] else { return nil }
            return .object(["id": .int(Int(id)), "app": entry.app.map(JSON.string) ?? .null,
                            "title": entry.title.map(JSON.string) ?? .null, "floating": .bool(entry.floating),
                            "workspace": entry.workspace.map(JSON.string) ?? .null])
        }
        let shownNames = Set(shown.values)
        let workspaces = snapshot.workspaceNames.sorted().map { name in
            JSON.object(["name": .string(name), "label": labels[name].map(JSON.string) ?? .null,
                         "shown": .bool(shownNames.contains(name))])
        }
        let displays = snapshot.displays.keys.sorted().map { id in
            JSON.object(["id": .string(id), "name": .string(snapshot.displays[id] ?? ""),
                         "workspace": snapshot.workspaces[id].map(JSON.string) ?? .null,
                         "layout": snapshot.layouts[id].map(JSON.string) ?? .null])
        }
        return .object(["focused": snapshot.focused.map { .int(Int($0)) } ?? .null, "windows": .array(windows),
                        "workspaces": .array(workspaces), "displays": .array(displays)])
    }
}
