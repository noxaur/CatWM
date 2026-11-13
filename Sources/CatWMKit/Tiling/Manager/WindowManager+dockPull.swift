import AppKit

extension WindowManager {
    package func prepareDockPull(at point: CGPoint) -> (@MainActor @Sendable () -> Void)? {
        let deadline = Date().addingTimeInterval(0.15)
        guard isStarted, config.virtualWorkspaces, !closeAndSort.sortSession, dockArea.contains(point),
              Spaces.canMoveWindows,
              let display = backend.screens().first(where: { $0.frame.contains(point) }),
              isOnHomeSpace(display), let workspace = virtualShown[display.uuid],
              let app = dockApplication(at: point),
              !AXStalls.shared.isStalled(app.processIdentifier) else { return nil }
        let appElement = axApp(app.processIdentifier, timeout: 0.03)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused)
            != .cannotComplete else { return nil }
        let known = focusOrder.compactMap { windows[$0] }.filter { $0.pid == app.processIdentifier }.map(\.element)
        defer { known.forEach { AXUIElementSetMessagingTimeout($0, Window.messagingTimeout) } }
        let focusedWindow = focused.flatMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? unsafeDowncast($0, to: AXUIElement.self) : nil
        }
        let candidates = [focusedWindow, appElement.element(kAXMainWindowAttribute)]
            .compactMap(\.self) + known + appElement.elements(kAXWindowsAttribute)
        let desktops = Set(backend.screens().flatMap { screen -> [UInt64] in
            guard let info = Spaces.list(display: screen.uuid) else { return [] }
            return info.desktops.map { info.ids[$0] }
        })
        var seen: Set<CGWindowID> = []
        for candidate in candidates {
            guard Date() < deadline else { return nil }
            AXUIElementSetMessagingTimeout(candidate, 0.03)
            guard let id = candidate.windowID, seen.insert(id).inserted else { continue }
            guard candidate.string(kAXSubroleAttribute) == kAXStandardWindowSubrole else { continue }
            let membership = Spaces.of(window: id)
            guard membership.count == 1, let source = membership.first,
                  desktops.contains(source), source != backend.currentSpace(display: display.uuid),
                  !nativeMoves.isMoving(id), !candidate.flag(kAXMinimizedAttribute),
                  !candidate.flag("AXFullScreen") else { return nil }
            let window = windows[id]
                ?? Window(id: id, element: candidate, pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                          backend: backend)
            return { [weak self] in
                guard let self, config.virtualWorkspaces, virtualShown[display.uuid] == workspace,
                      isOnHomeSpace(display), window.isValid else { return }
                if window.naturalFrame.isNull {
                    readDirectActionFacts(window)
                    window.autoFloating = shouldFloat(window)
                }
                cancelFocusRequest()
                surface.leaveMode()
                moveWindow(window, toWorkspace: workspace, follow: true)
            }
        }
        return nil
    }

    private func dockApplication(at point: CGPoint) -> NSRunningApplication? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let dockElement = axApp(dock.processIdentifier, timeout: 0.03)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dockElement, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        AXUIElementSetMessagingTimeout(hit, 0.03)
        guard hit.string(kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = hit.value(kAXURLAttribute) as? URL,
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
              }), app.processIdentifier != getpid(), !app.isHidden else { return nil }
        return app
    }
}
