import AppKit
import CatWMKit
import os

extension FakeBackend {
    private static let defaults = Config.parse(defaultText)

    @MainActor package func makeManager(_ configure: (inout Config) -> Void = { _ in }) -> WindowManager {
        var config = Self.defaults
        config.virtualWorkspaces = false
        config.animate = false
        config.mouseFollowsFocus = false
        config.focusFollowsMouse = false
        config.windowMargins = false
        config.paddingLeft = 0; config.paddingRight = 0; config.paddingTop = 0; config.paddingBottom = 0
        configure(&config)
        let manager = WindowManager(backend: self, config: config)
        manager.animator = Animator(backend: self, now: clock.now, delay: clock.delay)
        state.withLockUnchecked { $0.clockedAnimators.insert(ObjectIdentifier(manager.animator)) }
        manager.startEngine()
        return manager
    }

    @MainActor @discardableResult
    package func settle(_ manager: WindowManager, rounds: Int = 8, timeout: TimeInterval = 60) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var rounds = rounds, steps = rounds * 4
        while rounds > 0 {
            let before = writes.count
            let scanned = await bounded(until: deadline) { waiter in
                manager.scanAndRefresh { waiter.finish(true) }
                let request = manager.scanRequests
                return { manager.scanWaiters.removeAll { $0.request == request } }
            }
            guard scanned, await bounded(until: deadline, { waiter in
                manager.animator.afterPendingWrites { waiter.finish(true) }
                return {}
            }) else { return false }
            if ids.contains(where: manager.animator.isAnimating) {
                let landed = manager.animator.onLanded
                guard await bounded(until: deadline, { waiter in
                    let check = { if !self.ids.contains(where: manager.animator.isAnimating) { waiter.finish(true) } }
                    manager.animator.onLanded = { landed?(); check() }
                    check()
                    return { manager.animator.onLanded = landed }
                }) else { return false }
                continue
            }
            let wrote = writes.count != before
            let clocked = state.withLockUnchecked { $0.clockedAnimators.contains(ObjectIdentifier(manager.animator)) }
            let held = clocked ? ids.compactMap(manager.animator.quietEnd) : []
            if let next = (held + [clock.nextDue].compactMap(\.self)).min() {
                guard steps > 0 else { return false }
                steps -= 1
                clock.advance(by: max(next - clock.now(), 0))
                if wrote { rounds -= 1 }
                continue
            }
            if !wrote, Set(manager.windows.keys) == ids { return true }
            rounds -= 1
        }
        return false
    }

    @MainActor @discardableResult
    package func wait(_ manager: WindowManager, timeout: TimeInterval = 60,
                      until condition: @escaping () -> Bool) async -> Bool {
        guard !condition() else { return true }
        return await bounded(until: Date().addingTimeInterval(timeout)) { waiter in
            manager.onChange = { if condition() { waiter.finish(true) } }
            self.observeCursorRefresh { if condition() { waiter.finish(true) } }
            return {
                manager.onChange = nil
                self.observeCursorRefresh(nil)
            }
        }
    }

    @MainActor private func bounded(until deadline: Date,
                                    _ start: @escaping (Waiter) -> () -> Void) async -> Bool {
        let waiter = Waiter()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { done in
                waiter.start(done, until: deadline, start)
                if Task.isCancelled { waiter.finish(false) }
            }
        } onCancel: {
            Task { @MainActor in waiter.finish(false) }
        }
    }

    @MainActor private final class Waiter {
        private var done: CheckedContinuation<Bool, Never>?
        private var deadline: DispatchSourceTimer?
        private var cleanUp: (() -> Void)?

        func start(_ done: CheckedContinuation<Bool, Never>, until end: Date, _ start: (Waiter) -> () -> Void) {
            self.done = done
            let deadline = DispatchSource.makeTimerSource(queue: .main)
            deadline.schedule(deadline: .now() + max(end.timeIntervalSinceNow, 0))
            deadline.setEventHandler { [weak self] in self?.finish(false) }
            deadline.resume()
            self.deadline = deadline
            let cleanUp = start(self)
            if self.done == nil { cleanUp() } else { self.cleanUp = cleanUp }
        }

        func finish(_ met: Bool) {
            guard let done else { return }
            self.done = nil
            deadline?.cancel()
            deadline = nil
            cleanUp?()
            cleanUp = nil
            done.resume(returning: met)
        }
    }
}
