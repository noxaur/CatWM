import AppKit

extension WindowManager {
    package func cycleFocus(_ delta: Int) {
        guard let current = context(), !current.ids.isEmpty else { return }
        let ids = current.ids
        let i = current.window.flatMap { ids.firstIndex(of: $0.id) } ?? (delta > 0 ? -1 : 0)
        let next = ids[i.wrapped(by: delta, in: ids.count)]
        if let window = windows[next] { focus(window) }
    }

    package func cycleSwap(_ delta: Int) {
        guard let current = context(), let window = current.window,
              let i = current.ids.firstIndex(of: window.id), current.ids.count > 1 else { return }
        let ids = current.ids
        swapOrder(window.id, ids[i.wrapped(by: delta, in: ids.count)])
        refresh()
    }

    package func swapWithMain() {
        guard let current = context(), let window = current.window,
              current.ids.count > 1, current.ids.contains(window.id) else { return }
        swapOrder(window.id, current.ids[0] == window.id ? current.ids[1] : current.ids[0])
        refresh()
        focus(window)
    }

    package func focusMain() {
        guard let current = context(), let id = current.ids.first, let window = windows[id] else { return }
        focus(window)
    }

    package func changeMainCount(_ delta: Int) {
        guard let current = context() else { return }
        current.state.mainCount = max(1, min(10, current.state.mainCount + delta))
        corrections = [:]
        refresh()
    }

    package func adjustRatio(_ arg: String) {
        guard let current = context() else { return }
        let parts = arg.lowercased().split(separator: " ")
        let exact = parts.first == "exact" && parts.count > 1 ? Double(parts[1]).map { CGFloat($0) } : nil
        let delta = Double(arg.replacingOccurrences(of: "+", with: "")).map { CGFloat($0) } ?? config.windowResizeStep
        if current.state.layout == .dwindle {
            current.state.ratio = SplitDivider.clamped(exact ?? current.state.ratio + delta)
            changeDwindle(of: current.window) { tree, index, area in
                guard let ratio = tree.setRatio(at: index, in: area, { exact ?? $0 + delta }) else { return }
                current.state.ratio = ratio
            }
            return
        }
        let ratio = SplitDivider.clamped(exact ?? current.state.ratio + delta)
        if let stubborn = windowRefusingRatio(ratio, from: current.state.ratio, ids: current.ids,
                                              on: current.screen, current.state) {
            warnTooSmall(stubborn, on: current.screen)
            return
        }
        current.state.ratio = ratio
        corrections = [:]
        dividerState.ratioChange = (current.screen.uuid, Date() + motion(on: current.screen).duration + 0.6)
        refresh()
    }

    package func cycleLayout(_ delta: Int) {
        guard let current = context() else { return }
        let layouts = config(on: current.screen).layouts
        guard !layouts.isEmpty else { return }
        let layout = current.state.layout
        let i = layouts.firstIndex(of: layout) ?? layout.mirrored.flatMap { layouts.firstIndex(of: $0) }
            ?? (delta > 0 ? -1 : 0)
        setLayout(layouts[i.wrapped(by: delta, in: layouts.count)], on: current.screen)
    }

    package func setLayout(_ layout: Layout, screen uuid: String) {
        guard let screen = backend.screens().first(where: { $0.uuid == uuid }) else { return }
        setLayout(layout, on: screen)
    }

    package func setLayout(_ layout: Layout, on screen: Screen) {
        let screenState = state(for: screen)
        tilingRecovery.fullscreen[workspaceKey(for: screen)] = nil
        screenState.layout = layout
        screenState.fullscreen = nil
        corrections = [:]
        refresh()
        if config.enablesLayoutHUD { surface.showHUD(layout.title, layout: layout, on: screen.nsScreen) }
    }

    package func swapOrder(_ first: CGWindowID, _ second: CGWindowID) {
        guard let i = order.firstIndex(of: first), let j = order.firstIndex(of: second) else { return }
        order.swapAt(i, j)
        let firstWorkspace = workspaceOf[first], secondWorkspace = workspaceOf[second]
        model.swapWorkspaces(first, second)
        if config.virtualWorkspaces, firstWorkspace != secondWorkspace {
            if let name = secondWorkspace, let window = windows[first] {
                moveNativeWindow(window, to: name, follow: false, from: firstWorkspace)
            }
            if let name = firstWorkspace, let window = windows[second] {
                moveNativeWindow(window, to: name, follow: false, from: secondWorkspace)
            }
        }
    }
}
