import AppKit

extension WindowActions {
    package static let targetable: Set<String> = [
        "togglefloating", "setfloating", "settiled", "resizeactive", "moveactive", "centerwindow", "fullscreen",
        "nativefullscreen", "minimize", "killactive", "movewindow", "movewindowtomonitor", "moveintogroup",
        "moveoutofgroup", "changegroupactive", "movegroupwindow", "movetoworkspace", "movetoworkspacesilent",
        "focuswindow", "unminimize", "pin", "movetoscratchpad"
    ]

    package static let focuswindow = WindowAction.text(
        "focuswindow", "focus", "Focus the window that a target names, on any workspace or display",
        .text("target", "A window target: \(WindowTarget.syntax)")
    ) { context in
        let manager = context.manager
        if context.arg.isEmpty, let window = context.target {
            return manager.focusAnywhere(window)
        }
        do {
            let target = try WindowTarget(context.arg)
            guard let window = manager.window(matching: target) else {
                return Log.info("focuswindow: no window matches \(context.arg)")
            }
            manager.focusAnywhere(window)
        } catch let failure as WindowTarget.Failure {
            Log.info("focuswindow: \(failure.message)")
        } catch {
            Log.info("focuswindow: \(error)")
        }
    }

    package static let focuslast = WindowAction(
        name: "focuslast", group: "focus", summary: "Focus the window that had focus before this one",
        pickers: [ActionPicker("Focus Last Window", .focus, "", "arrow.uturn.backward")]
    ) { $0.manager.focusLast() }
}

extension WindowManager {
    package func window(matching target: WindowTarget) -> Window? {
        let focused = focusedWindow()?.id
        let history = model.focusOrder
        func rank(_ window: Window) -> Int {
            window.id == focused ? -1 : history.firstIndex(of: window.id) ?? Int.max
        }
        return windows.values.filter { target.condition.holds(ruleFacts(of: $0)) }
            .min { (rank($0), $0.id) < (rank($1), $1.id) }
    }

    func resolveTarget(of dispatcher: String, in arg: String) -> (window: Window?, arg: String)? {
        let plugin = PluginDispatchers.isNamespaced(dispatcher.lowercased())
        guard let name = WindowActions.named(dispatcher)?.name ?? (plugin ? dispatcher : nil), arg.hasPrefix("@")
        else { return (nil, arg) }
        guard plugin || WindowActions.targetable.contains(name) else {
            Log.info("`\(name)` doesn't take a window target")
            return nil
        }
        do {
            guard let (target, rest) = try WindowTarget.leading(in: arg) else { return (nil, arg) }
            guard let window = window(matching: target) else {
                Log.info("\(name): no window matches \(arg)")
                return nil
            }
            return (window, rest)
        } catch let failure as WindowTarget.Failure {
            Log.info("\(name): \(failure.message)")
            return nil
        } catch {
            Log.info("\(name): \(error)")
            return nil
        }
    }

    package func focusAnywhere(_ window: Window) {
        if scratchpads.isHidden(window.id), let screen = currentScreen() {
            return show(scratchpadWindow: window, on: screen)
        }
        if config.virtualWorkspaces, let workspace = workspaceOf[window.id], isVirtual(workspace),
           !isShown(workspace) {
            return showWorkspace(workspace, focusing: window)
        }
        focus(window)
    }

    package func focusLast() {
        let current = focusedWindow()?.id
        guard let window = model.focusOrder.lazy.filter({ $0 != current }).compactMap({ self.windows[$0] })
            .first(where: { !$0.minimized && !scratchpads.isHidden($0.id) }) else { return }
        focusAnywhere(window)
    }
}
