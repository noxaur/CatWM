import AppKit

extension WindowManager {
    package func moveWorkspaceToMonitor(_ spec: String) {
        guard !restoringTemplate, let src = currentScreen() else { return }
        let screens = backend.screens()
        guard let dst = screen(from: src, spec: spec, in: screens), dst.uuid != src.uuid else { return }
        let focused = focusedWindow()
        let moving = windowsShown(on: src, in: screens)
        guard !moving.isEmpty else { return }
        for window in moving { relocate(window, from: src, to: dst) }
        refresh()
        scheduleRefresh()
        if let focused, moving.contains(where: { $0 === focused }) { focus(focused) }
    }

    package func swapWorkspaces(_ firstSpec: String, _ secondSpec: String) {
        guard !restoringTemplate, let origin = currentScreen() else { return }
        let screens = backend.screens()
        guard let first = screen(from: origin, spec: firstSpec, in: screens),
              let second = screen(from: origin, spec: secondSpec, in: screens),
              first.uuid != second.uuid else { return }
        let fromFirst = windowsShown(on: first, in: screens), fromSecond = windowsShown(on: second, in: screens)
        for window in fromFirst { relocate(window, from: first, to: second) }
        for window in fromSecond { relocate(window, from: second, to: first) }
        refresh()
        scheduleRefresh()
    }

    private func windowsShown(on screen: Screen, in screens: [Screen]) -> [Window] {
        guard let workspace = shown[screen.uuid] else { return [] }
        return order.compactMap { windows[$0] }.filter {
            workspaceOf[$0.id] == workspace && present.contains($0.id) && !tabs.isBehind($0.id)
                && self.screen(of: $0, in: screens)?.uuid == screen.uuid
        }
    }
}
