import AppKit
import QuartzCore

extension WindowManager {
    package func toggleFloating() {
        guard let window = focusedWindow() else { return }
        setFloating(!window.isFloating, for: window)
    }

    package func setFloating(_ floating: Bool, for window: Window) {
        guard window.isFloating != floating else { return }
        window.userFloating = .chosen(floating)
        floats.floatZoom[window.id] = nil
        if floating {
            targets[window.id] = nil
        } else {
            if let screen = screen(containing: window.cachedFrame) {
                assignManagedWindow(window.id, to: shown[screen.uuid])
            }
            corrections[window.id] = nil
        }
        refresh()
    }

    package func floatsFreely(_ id: CGWindowID) -> Bool {
        guard let window = windows[id] else { return false }
        if window.isFloating || !tilingEnabled { return true }
        guard let workspace = workspaceOf[id] else { return false }
        return (states[workspace]?.layout ?? config.layouts.first) == .floating
    }

    package func toggleZoom(of target: Window? = nil) {
        guard let window = target ?? focusedWindow(), let screen = screen(of: window) ?? currentScreen() else { return }
        let current = TilingContext(window: window, screen: screen, state: state(for: screen), ids: tiled(on: screen))
        if floatsFreely(window.id) { return toggleFloatZoom(window) }
        guard current.ids.contains(window.id) else { return }
        tilingRecovery.zoomed[workspaceKey(for: current.screen)] = nil
        current.state.zoomed = current.state.zoomed == window.id ? nil : window.id
        refresh()
        focus(window, warp: false)
    }

    package func toggleFloatZoom(_ window: Window) {
        guard let screen = screen(of: window) else { return }
        let fill = usableRect(screen).pixelAligned
        let frame = animator.destination(window.id) ?? window.cachedFrame
        let target: CGRect
        if let saved = floats.floatZoom.removeValue(forKey: window.id), frame.approxEqual(fill) {
            target = saved
        } else {
            floats.floatZoom[window.id] = frame
            target = fill
        }
        animator.animate([.init(window: window, to: target, bounds: screen.visible)],
                         spec: motion(of: window))
        focus(window, warp: false)
    }

    package func toggleMaximised() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        let known = focusedWindow().map { AXReference($0.element) }
        scanner.run(pid) { [weak self] in
            guard let element = known?.object ?? axApp(pid).element(kAXFocusedWindowAttribute) else { return }
            let isOn = element.flag("AXFullScreen")
            let done: Bool
            if element.isSettable("AXFullScreen") {
                done = element.set("AXFullScreen", isOn ? kCFBooleanFalse : kCFBooleanTrue)
            } else if let button = element.element("AXFullScreenButton") ?? element.element(kAXZoomButtonAttribute) {
                done = AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
            } else {
                done = false
            }
            let id = element.windowID
            DispatchQueue.main.async {
                self?.finishMaximisedToggle(id, app: app.bundleIdentifier, wasOn: isOn, done: done)
            }
        }
    }

    private func finishMaximisedToggle(_ id: CGWindowID?, app: String?, wasOn isOn: Bool, done: Bool) {
        Log.info(
            "native fullscreen \(isOn ? "off" : "on") for \(id.map(String.init) ?? "?") \(app ?? ""): "
                + (done ? "ok" : "refused")
        )
        guard done else { return }
        if let id, !isOn {
            for screen in backend.screens() where state(for: screen).zoomed == id { state(for: screen).zoomed = nil }
        }
        scheduleRefresh(after: 0.8)
    }

    package func adoptNativeZoom(_ window: Window) {
        scanner.run(window.pid) { [weak self] in
            let frame = window.backend.frame(of: window)
            DispatchQueue.main.async {
                guard let self, self.windows[window.id] === window, !window.isFloating,
                      !self.animator.isBusy(window.id), !frame.isNull,
                      NSEvent.pressedMouseButtons & 1 == 0,
                      let screen = self.screen(containing: frame),
                      self.shown[screen.uuid] == self.workspaceOf[window.id] else { return }
                let state = self.state(for: screen)
                let usable = self.usableRect(screen)
                let fills = frame.width >= usable.width * 0.95 && frame.height >= usable.height * 0.95
                if fills, state.zoomed != window.id {
                    state.zoomed = window.id
                } else if !fills, state.zoomed == window.id {
                    state.zoomed = nil
                }
                self.scheduleRefresh()
            }
        }
    }

    package func showMaximised(_ window: Window) -> Bool {
        guard config.virtualWorkspaces, window.maximised, let space = Spaces.of(window: window.id).first,
              let screen = backend.screens().first(where: {
                  Spaces.list(display: $0.uuid)?.ids.contains(space) == true
              }),
              backend.currentSpace(display: screen.uuid) != space else { return false }
        desktops.nativeWorkspaceGeneration += 1
        configureNativeController(focusing: window, focus: true, quiet: true,
                                  toward: Self.spaceWorkspace(display: screen.uuid, space: space))
        nativeDesktop.request(.init(workspace: Self.spaceWorkspace(display: screen.uuid, space: space),
                                    display: screen.uuid, space: space))
        return true
    }

    package func closeWindow(_ id: CGWindowID) -> Bool {
        guard let window = windows[id] else { return false }
        closeAndSort.lastClose = Date()
        markClosedTab(id)
        scanner.run(window.pid) { window.close() }
        return true
    }

    package func minimize(_ window: Window) {
        scanner.run(window.pid) { window.element.set(kAXMinimizedAttribute, kCFBooleanTrue) }
    }
}
