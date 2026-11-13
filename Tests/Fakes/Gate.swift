import Dispatch
import os

package final class Gate: Sendable {
    private let group = DispatchGroup()
    private let opened = OSAllocatedUnfairLock(initialState: false)

    package init() { group.enter() }

    deinit { open() }

    package func open() {
        guard opened.withLock({ wasOpen in defer { wasOpen = true }; return !wasOpen }) else { return }
        group.leave()
    }

    package func block() { group.wait() }

    package func wait() async {
        await withCheckedContinuation { continuation in
            group.notify(queue: .global()) { continuation.resume() }
        }
    }
}
