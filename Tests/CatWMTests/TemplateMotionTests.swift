import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import os
import Testing

@Suite @MainActor struct TemplateMotionTests {
    final class ResultBox: Sendable {
        private let stored = OSAllocatedUnfairLock(initialState: false)
        var value: Bool {
            get { stored.withLock { $0 } }
            set { stored.withLock { $0 = newValue } }
        }
    }

    @Test @MainActor func aShutdownBarrierDoesNotRequireTheMainQueue() {
        let animator = Animator()
        let completed = DispatchSemaphore(value: 0)
        animator.afterPendingWrites(pids: nil, completionQueue: .global(qos: .userInitiated)) { completed.signal() }
        #expect(completed.wait(timeout: .now() + 2) == .success)
    }

    @Test @MainActor func aLiftFollowsTheCursorOnTheSetCurve() {
        let animator = Animator()
        let window = Window(id: 9, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        let held = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(!animator.retarget(window, to: held))
        window.remember(.zero.insetBy(dx: -1, dy: -1))
        animator.animate([.init(window: window, to: held, bounds: held)],
                         duration: 5, curve: .spring, bounce: 0.3)
        #expect(animator.retarget(window, to: held.offsetBy(dx: 40, dy: 0)))
        #expect(animator.isBusy(window.id))
        animator.cancel(window.id)
        #expect(!animator.retarget(window, to: held))
    }

    @Test func cancellingAQueuedVerificationPreventsItsWrite() async {
        let writer = AXWriter(pid: getpid())
        let release = Gate()
        let ran = ResultBox()
        writer.run { release.block() }
        writer.run(for: 42) { _ in ran.value = true }
        writer.cancel(42)
        release.open()
        await drain(writer)
        #expect(!ran.value)
    }

    @Test func cancellingDuringReadInvalidatesTheFollowingWrite() async {
        let writer = AXWriter(pid: getpid())
        let release = Gate()
        let valid = ResultBox()
        await withCheckedContinuation { started in
            writer.run(for: 42) { isCurrent in
                started.resume()
                release.block()
                valid.value = isCurrent()
            }
        }
        writer.cancel(42)
        release.open()
        await drain(writer)
        #expect(!valid.value)
    }

    @Test func anotherWindowsCancellationDoesNotDropTheCurrentWrite() async {
        let writer = AXWriter(pid: getpid())
        let release = Gate()
        let ran = ResultBox()
        writer.run { release.block() }
        writer.run(for: 42) { isCurrent in ran.value = isCurrent() }
        writer.cancel(43)
        release.open()
        await drain(writer)
        #expect(ran.value)
    }

    @Test func collapsingDisplaysKeepsTheMainDisplaysLayoutAndFullscreenPriority() {
        var template = WorkspaceTemplateTests().template()
        template.displays.reverse()
        let preferred = TemplatePlacementPlan.preferredDisplays(
            template, mapping: ["external": "only", "builtin": "only"]
        )
        #expect(preferred == ["only": "external"])
    }

    @Test func separateDisplaysKeepTheirOwnLayoutAndFullscreenPriority() {
        let template = WorkspaceTemplateTests().template()
        let preferred = TemplatePlacementPlan.preferredDisplays(
            template, mapping: ["external": "desk", "builtin": "laptop"]
        )
        #expect(preferred == ["desk": "external", "laptop": "builtin"])
    }

    private func drain(_ writer: AXWriter) async {
        await withCheckedContinuation { continuation in writer.run { continuation.resume() } }
    }
}
