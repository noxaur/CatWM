import AppKit

extension WindowManager {
    package func screen(from source: Screen, spec: String, in screens: [Screen]) -> Screen? {
        if let dir = Direction(spec) {
            let center = source.center
            return screens.filter { other in
                switch dir {
                case .left: other.center.x < center.x - 1
                case .right: other.center.x > center.x + 1
                case .upward: other.center.y < center.y - 1
                case .down: other.center.y > center.y + 1
                }
            }.min {
                hypot($0.center.x - center.x, $0.center.y - center.y)
                    < hypot($1.center.x - center.x, $1.center.y - center.y)
            }
        }
        let i = screens.firstIndex { $0.uuid == source.uuid } ?? 0
        if spec.hasPrefix("+") || spec.hasPrefix("-"), let delta = Int(spec), !screens.isEmpty {
            return screens[((i + delta % screens.count) % screens.count + screens.count) % screens.count]
        }
        if let index = Int(spec), screens.indices.contains(index) { return screens[index] }
        return nil
    }

    package func screen(containing rect: CGRect) -> Screen? { screen(containing: rect, in: backend.screens()) }

    package func screen(containing rect: CGRect, in screens: [Screen]) -> Screen? {
        guard !rect.isNull else { return screens.first }
        return screens.max { first, second in
            let firstOverlap = first.frame.intersection(rect), secondOverlap = second.frame.intersection(rect)
            return (firstOverlap.isNull ? 0 : firstOverlap.width * firstOverlap.height)
                < (secondOverlap.isNull ? 0 : secondOverlap.width * secondOverlap.height)
        }
    }

    package func screen(of window: Window) -> Screen? { screen(of: window, in: backend.screens()) }

    package func screen(of window: Window, in screens: [Screen]) -> Screen? {
        if sharesSpaces {
            if !window.isFloating, let uuid = displayOf[window.id],
               let match = screens.first(where: { $0.uuid == uuid }) { return match }
        } else if config.virtualWorkspaces || !window.isFloating,
           let uuid = workspaceOf[window.id].flatMap({ monitorOf[$0] }),
           let match = screens.first(where: { $0.uuid == uuid }) { return match }
        return screen(containing: animator.destination(window.id) ?? window.cachedFrame, in: screens)
    }

    package func currentScreen() -> Screen? {
        let screens = backend.screens()
        if let window = focusedWindow(), let match = screen(of: window, in: screens) { return match }
        let point = mouseLocation()
        return screens.first { $0.frame.contains(point) } ?? screens.first
    }

    package var focusedScreen: NSScreen? { currentScreen()?.nsScreen }

    package func mouseLocation() -> CGPoint { backend.pointerLocation() }

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
            assignTabs(of: window.id, to: shown[dst.uuid])
            refresh()
        }
        if target == nil { focus(window) }
    }
}
