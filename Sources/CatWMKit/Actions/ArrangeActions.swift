import AppKit

extension WindowActions {
    private static let displayTargets = "`+1`, `-1`, `left`, `right`, `up`, `down` or a display number counting from 0"

    package static let balance = WindowAction(
        name: "balance", group: "layout", summary: "Give every tiled window the same area, as far as the layout allows",
        pickers: [ActionPicker("Balance Windows", .layout, "", "equal.square")]
    ) { $0.manager.balance() }

    package static let togglesplit = WindowAction(
        name: "togglesplit", group: "layout",
        summary: "Flip the split direction: Tall and Wide swap, and so do Column and Row",
        pickers: [ActionPicker("Flip Split Direction", .layout, "", "rectangle.split.2x1")]
    ) { $0.manager.toggleSplit() }

    package static let unminimize = WindowAction(
        name: "unminimize", group: "window", summary: "Bring back the minimized window of this workspace used last",
        pickers: [ActionPicker("Unminimize Window", .window, "", "arrow.up.left.and.arrow.down.right",
                               focusRequired: false)]
    ) { $0.manager.unminimize($0.target) }

    package static let moveworkspacetomonitor = WindowAction.text(
        "moveworkspacetomonitor", "displays",
        "Move the windows of this workspace to the workspace another display shows",
        .text("target", displayTargets)
    ) { $0.manager.moveWorkspaceToMonitor($0.arg) }

    package static let swapworkspaces = WindowAction.text(
        "swapworkspaces", "displays", "Swap the workspaces two displays show",
        .text("displays", "Two display targets, such as `0 1` or `left right`, found from the focused display. "
              + "Each is \(displayTargets).")
    ) { context in
        let displays = context.arg.split(whereSeparator: \.isWhitespace).map(String.init)
        guard displays.count == 2 else {
            return Log.info("swapworkspaces: expected two displays, got `\(context.arg)`")
        }
        context.manager.swapWorkspaces(displays[0], displays[1])
    }

    package static let sendshortcut = WindowAction.text(
        "sendshortcut", "app", "Press a key in the focused window's app, or in another app",
        .text("shortcut", "`<mods> <key> [bundle id]`, such as `cmd+shift t` or `ctrl tab com.apple.Safari`. "
              + "Only that app gets the key."),
        access: .keybindOnly
    ) { $0.manager.sendShortcut($0.arg, window: $0.target) }
}
