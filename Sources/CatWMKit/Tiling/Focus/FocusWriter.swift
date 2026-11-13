import AppKit
import os

@MainActor package final class FocusWriter {
    private let generation = OSAllocatedUnfairLock(initialState: 0)
    private var queues: [pid_t: DispatchQueue] = [:]
    private let apply: @Sendable (Window, @Sendable () -> Bool) -> Void

    package init(apply: @escaping @Sendable (Window, @Sendable () -> Bool) -> Void = { $0.focus(ifCurrent: $1) }) {
        self.apply = apply
    }

    package func cancel() { generation.withLock { $0 += 1 } }

    package func focus(_ window: Window, done: @escaping @MainActor () -> Void = {}) {
        let current = generation.withLock { $0 += 1; return $0 }
        let queue = queues[window.pid]
            ?? DispatchQueue(label: "catwm.focus-write.\(window.pid)", qos: .userInteractive)
        queues[window.pid] = queue
        let generation = generation, apply = apply
        queue.async {
            let isCurrent = { @Sendable in generation.withLock { $0 == current } }
            guard isCurrent() else { return }
            apply(window, isCurrent)
            DispatchQueue.main.async {
                guard isCurrent() else { return }
                done()
            }
        }
    }

    package func focusSink(_ window: CGWindowID) {
        let current = generation.withLock { $0 += 1; return $0 }
        let generation = generation
        DispatchQueue.global(qos: .userInteractive).async {
            guard generation.withLock({ $0 == current }) else { return }
            if !WindowServerFocus.focus(pid: getpid(), window: window) {
                DispatchQueue.main.async {
                    guard generation.withLock({ $0 == current }) else { return }
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    package func terminated(_ pid: pid_t) { queues[pid] = nil }
}
