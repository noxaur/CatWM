import AppKit

extension WindowManager {
    @MainActor package func dispatch(_ dispatcher: String, _ rawArg: String) {
        dispatch(dispatcher, rawArg, inMode: surface.inMode)
    }

    @MainActor package func dispatch(_ dispatcher: String, _ rawArg: String, inMode: Bool) {
        if let refusal = scopeRefusal(dispatcher) {
            Log.info(refusal)
            return
        }
        let arg = rawArg.trimmingCharacters(in: .whitespaces)
        if deferFocusCommand(dispatcher, arg: arg, inMode: inMode) { return }
        let timing = TilingTiming("command \(dispatcher)", windows: windows.count)
        defer { timing.finish() }
        defer { onDispatch?(dispatcher, arg, inMode) }
        if let effect = FocusEffect.all.first(where: { $0.dispatcher == dispatcher }) {
            surface.toggleFocusEffect(effect)
            return
        }
        guard let action = WindowActions.named(dispatcher) else {
            Log.info("unknown dispatcher \(dispatcher)")
            return
        }
        action.run(ActionContext(manager: self, arg: arg))
    }

    package func exec(_ cmd: String) {
        guard !cmd.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", cmd]
        Log.attempt("exec \(cmd)") { try process.run() }
    }

    package func moveWindowCommand(_ arg: String) {
        if arg.lowercased().hasPrefix("mon:") {
            moveToMonitor(String(arg.dropFirst(4)))
        } else if let direction = Direction(arg) {
            moveWindow(direction)
        }
    }

    package func setLayoutCommand(_ arg: String) {
        if let layout = Layout(rawValue: arg.lowercased()), let screen = currentScreen() {
            setLayout(layout, on: screen)
        }
    }

    package func showWorkspaceCommand(_ arg: String) {
        if config.virtualWorkspaces {
            if let workspace = resolveWorkspace(arg) { showWorkspace(workspace) }
        } else if let number = Int(arg) {
            switchSpace(number)
        }
    }

    package func moveToWorkspaceCommand(_ arg: String, follow: Bool, window target: Window? = nil) {
        if config.virtualWorkspaces {
            guard let workspace = resolveWorkspace(arg) else { return }
            moveFocusedWindow(to: workspace, follow: follow, window: target)
        } else if let number = Int(arg) {
            guard target == nil else {
                return Log.info("rules: moving a window to a Desktop needs CatWM workspaces, so \(arg) was skipped")
            }
            moveToSpace(number)
        }
    }

    package func layoutMessage(_ arg: String) {
        let parts = arg.split(separator: " ").map(String.init)
        guard let cmd = parts.first?.lowercased() else { return }
        switch cmd {
        case "swapwithmaster": swapWithMain()
        case "swapsides": swapSides()
        case "focusmaster": focusMain()
        case "addmaster": changeMainCount(1)
        case "removemaster": changeMainCount(-1)
        case "cyclenext": cycleFocus(1)
        case "cycleprev": cycleFocus(-1)
        case "swapnext": cycleSwap(1)
        case "swapprev": cycleSwap(-1)
        case "mfact": adjustRatio(parts.dropFirst().joined(separator: " "))
        case "orientationnext": cycleLayout(1)
        case "orientationprev": cycleLayout(-1)
        case "togglesplit": changeDwindle { $0.toggleSplit(at: $1, in: $2) }
        case "swapsplit": changeDwindle { $0.swapSplit(at: $1, in: $2) }
        default: Log.info("unknown layoutmsg \(cmd)")
        }
    }
}
