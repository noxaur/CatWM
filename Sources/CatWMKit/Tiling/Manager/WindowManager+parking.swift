import AppKit
import os

extension WindowManager {
    package func isParked(_ frame: CGRect, _ screens: [Screen]) -> Bool {
        guard !frame.isNull, frame.width > 0, frame.height > 0 else { return false }
        let onScreen = screens.reduce(CGFloat(0)) { sum, screen in
            let overlap = screen.frame.intersection(frame)
            return sum + (overlap.isNull ? 0 : overlap.width * overlap.height)
        }
        return onScreen < 400
    }

    private func parkingSpot(size: CGSize, on screen: Screen, _ screens: [Screen]) -> CGPoint {
        let right = CGPoint(x: screen.frame.maxX - 1, y: screen.frame.maxY - 1)
        let left = CGPoint(x: screen.frame.minX - size.width + 1, y: screen.frame.maxY - 1)
        for origin in [right, left] {
            let rect = CGRect(origin: origin, size: size)
            if !screens.contains(where: { $0.uuid != screen.uuid && $0.frame.intersects(rect) }) { return origin }
        }
        return right
    }

    private func monitorScreen(of id: CGWindowID, in screens: [Screen]) -> Screen? {
        workspaceOf[id].flatMap { monitorOf[$0] }.flatMap { uuid in screens.first { $0.uuid == uuid } }
            ?? screens.first
    }

    package func cornerPark(_ id: CGWindowID, screens: [Screen]) {
        guard let window = windows[id], let screen = monitorScreen(of: id, in: screens) else { return }
        let size = (animator.destination(id) ?? window.cachedFrame).size
        let frame = CGRect(origin: parkingSpot(size: size, on: screen, screens), size: size)
        guard !animator.isMoving(id, to: frame) else { return }
        animator.position(window, at: frame)
    }

    package func restoreHiddenWindows(completion: (@MainActor @Sendable () -> Void)? = nil) {
        cancelFocusRequest()
        let deliver: @Sendable () -> Void = {
            guard let completion else { return }
            RunLoop.main.perform(inModes: [.common, .modalPanel]) { onMainThread { completion() } }
        }
        guard config.virtualWorkspaces || !shown.isEmpty else { deliver(); return }
        let screens = backend.screens()
        guard !screens.isEmpty else { deliver(); return }
        saveWorkspaces()
        saveTilingRecovery()
        for (id, window) in windows {
            let frame = animator.destination(id) ?? window.cachedFrame
            animator.cancel(id)
            guard isParked(frame, screens) else { continue }
            guard let screen = screen(of: window, in: screens) ?? screens.first else { continue }
            var rect = floats.floatFrames[id] ?? targets[id]
                ?? CGRect(x: screen.visible.midX - frame.width / 2, y: screen.visible.midY - frame.height / 2,
                          width: frame.width, height: frame.height)
            rect.size.width = min(rect.width, screen.visible.width)
            rect.size.height = min(rect.height, screen.visible.height)
            rect.origin.x = max(screen.visible.minX, min(rect.origin.x, screen.visible.maxX - rect.width))
            rect.origin.y = max(screen.visible.minY, min(rect.origin.y, screen.visible.maxY - rect.height))
            animator.animate([.init(window: window, to: rect, bounds: screen.visible)], duration: 0)
        }
        Log.info("workspaces: queued parked windows for restoration")
        if completion != nil {
            let finished = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable () -> Void = {
                let first = finished.withLock { done in
                    guard !done else { return false }
                    done = true
                    return true
                }
                guard first else { return }
                deliver()
            }
            let queue = DispatchQueue.global(qos: .userInitiated)
            animator.afterPendingWrites(pids: nil, completionQueue: queue, finish)
            queue.asyncAfter(deadline: .now() + 2, execute: finish) // style-ok: limit for a hung app
        }
    }
}
