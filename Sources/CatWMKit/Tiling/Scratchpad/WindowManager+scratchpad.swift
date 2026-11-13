import AppKit

extension WindowManager {
    package func moveToScratchpad(_ window: Window, named raw: String) {
        guard !window.fullscreen, !window.minimized else { return }
        pins.forget(window.id)
        scratchpads.stash(window.id, as: Scratchpads.name(raw))
        park(scratchpadWindow: window)
    }

    package func toggleScratchpad(named raw: String) {
        let name = Scratchpads.name(raw)
        guard let screen = currentScreen() else { return }
        let here = shown[screen.uuid]
        let open = scratchpads.shown(named: name).filter { workspaceOf[$0] == here && visible.contains($0) }
        if !open.isEmpty {
            for window in open.compactMap({ windows[$0] }) {
                scratchpads.hide(window.id)
                park(scratchpadWindow: window)
            }
            return
        }
        guard let window = (scratchpads.lastHidden(named: name) ?? scratchpads.shown(named: name).last)
            .flatMap({ windows[$0] }) else {
            surface.showHUD("No window in scratchpad \(name)", on: screen.nsScreen)
            return
        }
        show(scratchpadWindow: window, on: screen)
    }

    package func setPinned(_ pinned: Bool, _ window: Window) {
        let id = window.id
        guard pinned else { return pins.forget(id) }
        guard !pins.contains(id), !scratchpads.isHidden(id) else { return }
        scratchpads.forget(id)
        pins.pin(id)
        setFloating(true, for: window)
    }

    private func park(scratchpadWindow window: Window) {
        let id = window.id
        let screens = backend.screens()
        let frame = animator.destination(id) ?? window.cachedFrame
        if !isParked(frame, screens) { floats.floatFrames[id] = frame }
        window.userFloating = .chosen(true)
        floats.floatZoom[id] = nil
        targets[id] = nil
        let workspace = workspaceOf[id]
        let hadFocus = focusedWindow()?.id == id
        cornerPark(id, screens: screens)
        refresh()
        if hadFocus, let workspace { handOffFocus(from: workspace) }
    }

    private func show(scratchpadWindow window: Window, on screen: Screen) {
        let id = window.id
        scratchpads.reveal(id)
        floats.floatFrames[id] = nil
        floats.floatZoom[id] = nil
        targets[id] = nil
        animator.cancel(id)
        animator.animate([.init(window: window, to: scratchpadFrame(of: window, on: screen), bounds: screen.visible)],
                         duration: 0)
        if config.virtualWorkspaces, let workspace = shown[screen.uuid], workspaceOf[id] != workspace {
            moveNativeWindow(window, to: workspace, follow: true)
        } else {
            refresh()
            focus(window)
        }
    }

    private func scratchpadFrame(of window: Window, on screen: Screen) -> CGRect {
        let area = screen.visible
        let scale = CGFloat(config.scratchpadSize) / 100
        var size = window.resizable
            ? CGSize(width: area.width * scale, height: area.height * scale)
            : (animator.destination(window.id) ?? window.cachedFrame).size
        if let minimum = minSizes[window.id] { size = CGSize(width: max(size.width, minimum.width),
                                                             height: max(size.height, minimum.height)) }
        size = CGSize(width: min(size.width, area.width), height: min(size.height, area.height))
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                      width: size.width, height: size.height).pixelAligned
    }

    func followPinnedWindows() {
        guard config.virtualWorkspaces, !pins.ids.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, isStarted, !restoringTemplate, !nativeDesktop.isRunning, nativeDesktop.requested == nil,
                  !desktops.nativeCreationBusy else { return }
            for id in pins.ids.sorted() {
                guard let window = windows[id], !window.minimized, !window.fullscreen, !nativeMoves.isBusy(id),
                      let from = workspaceOf[id], isVirtual(from), let display = monitorOf[from],
                      let target = virtualShown[display], target != from, pins.claimFollow(id) else { continue }
                moveNativeWindow(window, to: target, follow: false)
            }
        }
    }

    func carryPinnedWindows(to workspace: String, space: UInt64, display: String) {
        for id in pins.ids.sorted() {
            guard let window = windows[id], !window.minimized, !window.fullscreen, !nativeMoves.isBusy(id),
                  let from = workspaceOf[id], from != workspace, isVirtual(from),
                  monitorOf[from] == display else { continue }
            animator.cancel(id)
            nativeMoves.follow(.init(window: window, workspace: workspace, space: space, from: from))
        }
    }

    package func handOffFocus(from workspace: String) {
        guard isShown(workspace) else { return }
        let remaining = order.filter { workspaceOf[$0] == workspace && visible.contains($0) }
        if let next = (model.mostRecent(of: remaining) ?? remaining.first).flatMap({ windows[$0] }) {
            focus(next)
        } else if let screen = backend.screens().first(where: { $0.uuid == monitorOf[workspace] }) {
            parkFocus(on: screen)
        } else {
            parkFocus()
        }
    }
}
