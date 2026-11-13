import AppKit

extension WindowManager {
    package func exec(_ cmd: String) {
        guard !cmd.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", cmd]
        Log.attempt("exec \(cmd)") { try process.run() }
    }

    package func focusMonitor(_ spec: String) {
        guard let src = currentScreen(), let dst = screen(from: src, spec: spec, in: backend.screens()) else { return }
        focus(on: dst)
    }

    package func moveToMonitor(_ spec: String, window target: Window? = nil) {
        guard !restoringTemplate else { return }
        let screens = backend.screens()
        guard let window = target ?? focusedWindow(), let src = screen(of: window, in: screens),
              let dst = screen(from: src, spec: spec, in: screens), dst.uuid != src.uuid else { return }
        if window.isFloating {
            let frame = window.cachedFrame
            var origin = CGPoint(x: dst.visible.minX + (frame.minX - src.visible.minX),
                                 y: dst.visible.minY + (frame.minY - src.visible.minY))
            origin.x = max(dst.visible.minX, min(origin.x, dst.visible.maxX - frame.width))
            origin.y = max(dst.visible.minY, min(origin.y, dst.visible.maxY - frame.height))
            animator.animate([.init(window: window, to: CGRect(origin: origin, size: frame.size), bounds: dst.visible)],
                             spec: motion(of: window))
            assignManagedWindow(window.id, to: shown[dst.uuid])
            scheduleRefresh()
        } else if sharesSpaces {
            for member in tabs.group(of: window.id)?.members ?? [window.id] {
                displayOf[member] = dst.uuid
                corrections[member] = nil
            }
            refresh()
        } else {
            move(window, toDisplay: dst)
        }
        if target == nil { focus(window) }
    }

    package func move(_ window: Window, toDisplay screen: Screen) {
        assignTabs(of: window.id, to: shown[screen.uuid])
        refresh(recording: [window.id: screen.uuid])
    }

    package func refresh(recording destinations: [CGWindowID: String]) {
        refresh()
        for (id, display) in destinations {
            for member in tabs.group(of: id)?.members ?? [id] where animator.isBusy(member) {
                displayOf[member] = display
            }
        }
    }
}
