import AppKit

extension WindowActions {
    package static let movetoscratchpad = WindowAction.text(
        "movetoscratchpad", "window", "Hide the focused window in a scratchpad and float it",
        .text("name", "The scratchpad's name. The default is `scratchpad`.", required: false)
    ) { context in
        if let window = context.window { context.manager.moveToScratchpad(window, named: context.arg) }
    }

    package static let togglescratchpad = WindowAction.text(
        "togglescratchpad", "window",
        "Show a scratchpad window floating over this workspace, or hide it again",
        .text("name", "The scratchpad's name. The default is `scratchpad`.", required: false)
    ) { $0.manager.toggleScratchpad(named: $0.arg) }

    package static let pin = WindowAction.text(
        "pin", "window", "Float the focused window and keep it on every workspace of its display",
        .choice("mode", ["on", "off", "toggle"], "The default is `toggle`.", required: false)
    ) { context in
        guard let window = context.window else { return }
        let pinned = context.manager.pins.contains(window.id)
        let wanted: Bool
        switch context.arg.lowercased() {
        case "on": wanted = true
        case "off": wanted = false
        default: wanted = !pinned
        }
        context.manager.setPinned(wanted, window)
    }
}
