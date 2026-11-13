import AppKit

extension WindowManager {
    package func balance() {
        guard let current = context() else { return }
        let layout = current.state.layout
        guard let ratio = layout.balancedRatio(count: current.ids.count, mainCount: current.state.mainCount) else {
            return Log.info("balance: \(layout.title) with \(current.ids.count) windows has no uneven split")
        }
        adjustRatio("exact \(ratio)")
    }

    package func toggleSplit() {
        guard let screen = currentScreen() else { return }
        let layout = state(for: screen).layout
        guard let flipped = layout.transposed else {
            return Log.info("togglesplit: \(layout.title) has no split direction to flip")
        }
        setLayout(flipped, on: screen)
    }

    package func unminimize(_ target: Window? = nil) {
        let window: Window?
        if let target {
            window = target.minimized ? target : nil
        } else {
            let workspace = currentScreen().flatMap { shown[$0.uuid] }
            let hidden = order.filter { windows[$0]?.minimized == true && workspaceOf[$0] == workspace }
            window = (model.mostRecent(of: hidden) ?? hidden.last).flatMap { windows[$0] }
        }
        guard let window else { return Log.info("unminimize: no minimized window on this workspace") }
        scanner.run(window.pid) { [weak self] in
            window.backend.setMinimized(window, false)
            DispatchQueue.main.async {
                self?.scheduleRefresh(after: 0)
                self?.focus(window)
            }
        }
    }

    package func sendShortcut(_ arg: String, window target: Window? = nil) {
        var tokens = arg.split(whereSeparator: \.isWhitespace)
        var mods: NSEvent.ModifierFlags = []
        while let flags = tokens.first.flatMap({ ConfigText.flags(String($0)) }) {
            mods.formUnion(flags)
            tokens.removeFirst()
        }
        guard let key = tokens.first, let code = keyCodes[key.lowercased()], code < SpecialKey.mouseUp,
              tokens.count <= 2 else {
            return Log.info("sendshortcut: expected `<mods> <key> [bundle id]`, got `\(arg)`")
        }
        let pid: pid_t?
        if tokens.count == 2 {
            let bundle = tokens[1].lowercased()
            pid = order.compactMap { windows[$0] }.first { $0.bundleID?.lowercased() == bundle }?.pid
        } else {
            pid = (target ?? focusedWindow())?.pid
        }
        guard let pid else { return Log.info("sendshortcut: no app to send \(key) to") }
        backend.post(keyCode: code, flags: CGEventFlags(rawValue: UInt64(mods.rawValue)), toPID: pid)
    }
}
