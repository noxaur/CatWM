import AppKit

extension WindowManager {
    package func focus(_ window: Window, warp: Bool = true) {
        let request = focusRequests.begin(id: window.id, pid: window.pid, origin: frontmostPID())
        animator.focus(window) { [weak self] in
            guard let self, self.focusRequests.executed(request) else { return }
            self.requestFocusObservation()
        }
        noteFocus(window.id)
        if warp, config.mouseFollowsFocus {
            ignoreMouseUntil = Date().addingTimeInterval(0.3)
            warpPointer(to: navFrame(window).center)
        } else {
            cursorRefresh.soon()
        }
    }

    package func noteFocus(_ id: CGWindowID) { model.noteFocus(id) }

    package func focusedWindowState() -> (floating: Bool, fullscreen: Bool)? {
        guard let window = focusedWindow() else { return nil }
        if floatsFreely(window.id) { return (window.isFloating, floats.floatFullscreen[window.id] != nil) }
        let fullscreen = screen(of: window).map { state(for: $0).fullscreen == window.id } ?? false
        return (window.isFloating, fullscreen)
    }

    package func focusedWindow() -> Window? {
        switch focusRequests.resolvePending(frontmost: frontmostPID(), available: { id in
            windows[id] != nil && visible.contains(id)
        }) {
        case .none: break
        case .window(let id): return windows[id]
        case .cancelled: animator.cancelFocus()
        }
        return reportedFocusedWindow()
    }

    package func reportedFocusedWindow() -> Window? {
        guard let pid = frontmostPID(),
              let report = focusRequests.reportedFocus, report.pid == pid,
              let id = report.id else { return nil }
        return windows[id]
    }

    package func navFrame(_ window: Window) -> CGRect {
        (!window.isFloating && tilingEnabled ? targets[window.id] : nil)
            ?? animator.destination(window.id) ?? window.cachedFrame
    }

    package func followFocus() {
        guard isStarted, !restoringTemplate, let window = reportedFocusedWindow() else { return }
        guard focusRequests.confirm(window.id) else { return }
        noteFocus(window.id)
        guard !closeAndSort.sortSession else { return }
        guard config.virtualWorkspaces, let workspace = workspaceOf[window.id], isVirtual(workspace) else { return }
        if isShown(workspace) { lastFocused[workspace] = window.id; return }
        guard Date() > autoSwitchAfter else { return }
        guard isParked(window.cachedFrame, backend.screens()) else { scheduleRefresh(); return }
        if config.stayOnWorkspaceAfterClose, Date().timeIntervalSince(closeAndSort.lastClose) < 1.0 {
            Log.debug("workspaces: ignoring focus on \(workspace) right after a close")
            refocusCurrentWorkspace()
            return
        }
        Log.info("workspaces: \(window.bundleID ?? "a window") on workspace \(workspace) was focused; switching")
        showWorkspace(workspace, focusing: window)
    }

    package func refocusCurrentWorkspace() {
        guard let screen = currentScreen(), let cur = virtualShown[screen.uuid] else { return parkFocus() }
        let candidates = [lastFocused[cur]].compactMap(\.self) + order
        if let id = candidates.first(where: { visible.contains($0) && workspaceOf[$0] == cur }),
           let window = windows[id] {
            focus(window)
        } else {
            parkFocus()
        }
    }
}
