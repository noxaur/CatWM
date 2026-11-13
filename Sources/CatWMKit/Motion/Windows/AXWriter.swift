import AppKit
import os
import QuartzCore

package final class AXWriter: Sendable {
    package struct Step: Sendable {
        package let shown: CFTimeInterval, presentation: CFTimeInterval
        package let observed: CGRect?

        package init(shown: CFTimeInterval, presentation: CFTimeInterval, observed: CGRect? = nil) {
            (self.shown, self.presentation, self.observed) = (shown, presentation, observed)
        }

        package var period: Double { presentation - shown }
    }
    private enum Operation: Sendable {
        case step(Step, frame: @Sendable (WindowLead.Times) -> CGRect)
        case land(CGRect, done: @MainActor (Bool) -> Void), position(CGPoint, done: @MainActor (Bool) -> Void)
        case follow(CGRect, done: @MainActor (CGSize?) -> Void)
    }
    private struct Pending: Sendable {
        let window: Window
        let operation: Operation
        let epoch: Int
        let releasesSpace: Bool
    }
    private struct Attempt {
        let call: WindowLead.Call
        let applied: Bool
    }
    private struct Write {
        var position: Attempt?, size: Attempt?
        var applied: Bool { position?.applied != false && size?.applied != false }
        var seconds: Double { (position?.call.seconds ?? 0) + (size?.call.seconds ?? 0) }
    }
    private struct Prepared {
        let lead: WindowLead
        let previous: CGSize?
        let animating: Bool
    }
    package struct Stats: Sendable { var size = Stat(), position = Stat(), land = Stat(), skipped = 0 }

    private struct Tracked: Sendable {
        var epoch = 0
        var animating = false
        var lastSize: CGSize?
        var lead: WindowLead
        var observations: [WindowLead.Observation] = []
    }
    private struct State: Sendable {
        var pending: [CGWindowID: Pending] = [:]
        var windows: [CGWindowID: Tracked] = [:]
        var learned: CGWindowID?
        var draining = false
        var stats = Stats()

        func lead(_ id: CGWindowID) -> WindowLead {
            windows[id]?.lead ?? learned.flatMap { windows[$0]?.lead.inherited } ?? WindowLead()
        }

        mutating func track(_ id: CGWindowID) {
            if windows[id] == nil { windows[id] = Tracked(lead: lead(id)) }
        }
    }

    package let pid: pid_t
    private let backend: any WindowBackend
    private let now: @Sendable () -> CFTimeInterval
    private let queue: DispatchQueue
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let enhancedUI: EnhancedUI

    package init(pid: pid_t, backend: any WindowBackend = AXBackend.shared,
                 now: @escaping @Sendable () -> CFTimeInterval = CACurrentMediaTime) {
        self.pid = pid
        self.backend = backend
        self.now = now
        enhancedUI = EnhancedUI(pid: pid, backend: backend)
        queue = DispatchQueue(label: "catwm.ax.\(pid)", qos: .userInteractive)
    }

    package func step(_ window: Window, _ step: Step, releasesSpace: Bool = false,
                      to frame: @escaping @Sendable (WindowLead.Times) -> CGRect) {
        submit(window, .step(step, frame: frame), releasesSpace: releasesSpace)
    }

    package func land(_ window: Window, at frame: CGRect, done: @escaping @MainActor (Bool) -> Void) {
        submit(window, .land(frame, done: done))
    }

    package func follow(_ window: Window, to frame: CGRect, done: @escaping @MainActor (CGSize?) -> Void) {
        submit(window, .follow(frame, done: done))
    }

    package func position(_ window: Window, at point: CGPoint, done: @escaping @MainActor (Bool) -> Void) {
        submit(window, .position(point, done: done))
    }

    package func leadFrames(_ id: CGWindowID, at now: CFTimeInterval, _ step: Step) -> Int {
        state.withLock { $0.lead(id) }
            .plan(at: now, presentation: step.presentation, period: step.period).frames.max() ?? 0
    }

    package func cancel(_ id: CGWindowID) {
        state.withLock { state in
            state.pending[id] = nil
            state.track(id)
            state.windows[id]?.epoch += 1
            state.windows[id]?.observations = []
        }
        queue.async { [self] in
            let wasAnimating = state.withLock { state in
                defer { state.windows[id]?.animating = false; state.windows[id]?.lastSize = nil }
                return state.windows[id]?.animating == true
            }
            if wasAnimating { enhancedUI.resume() }
        }
    }

    package func forget(_ id: CGWindowID) {
        queue.async { [self] in
            state.withLock { state in
                state.windows[id] = nil
                if state.learned == id { state.learned = nil }
            }
        }
    }

    package func run(_ work: @escaping @Sendable () -> Void) { queue.async(execute: work) }

    package func suspendEnhancedUI() { enhancedUI.suspend() }
    package func resumeEnhancedUI() { enhancedUI.resume() }

    package func run(for id: CGWindowID, _ work: @escaping @Sendable (_ isCurrent: () -> Bool) -> Void) {
        let epoch = state.withLock { $0.windows[id]?.epoch ?? 0 }
        queue.async { [self] in
            let isCurrent = { self.state.withLock { ($0.windows[id]?.epoch ?? 0) == epoch } }
            guard isCurrent() else { return }
            work(isCurrent)
        }
    }

    package func takeStats() -> Stats {
        state.withLock { state in defer { state.stats = Stats() }; return state.stats }
    }

    private func submit(_ window: Window, _ operation: Operation, releasesSpace: Bool = false) {
        let id = window.id
        let start = state.withLock { state -> Bool in
            state.track(id)
            if case .step = state.pending[id]?.operation { state.stats.skipped += 1 }
            if case let .step(step, _) = operation, let observed = step.observed {
                state.windows[id]?.observations.append(.init(frame: observed, shown: step.shown, period: step.period))
                if state.windows[id]?.observations.count ?? 0 > MotionTiming.leadHistory {
                    state.windows[id]?.observations.removeFirst()
                }
            }
            state.pending[id] = Pending(window: window, operation: operation, epoch: state.windows[id]?.epoch ?? 0,
                                        releasesSpace: releasesSpace)
            defer { state.draining = true }
            return !state.draining
        }
        if start { queue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            let batch = state.withLock { state -> [Pending] in
                let items = state.pending.values.sorted {
                    $0.releasesSpace == $1.releasesSpace ? $0.window.id < $1.window.id : $0.releasesSpace
                }
                state.pending = [:]
                if items.isEmpty { state.draining = false }
                return items
            }
            if batch.isEmpty { return }
            for item in batch { apply(item) }
        }
    }

    private func refuse(_ item: Pending, wasAnimating: Bool) {
        if wasAnimating {
            state.withLock { $0.windows[item.window.id]?.animating = false }
            enhancedUI.resume()
        }
        switch item.operation {
        case let .land(_, done), let .position(_, done): DispatchQueue.main.async { done(false) }
        case let .follow(_, done): DispatchQueue.main.async { done(nil) }
        case .step: break
        }
    }

    private func apply(_ item: Pending) {
        let window = item.window, id = window.id
        let began = now()
        let prepared = state.withLock { state -> Prepared? in
            guard var tracked = state.windows[id], tracked.epoch == item.epoch else { return nil }
            if case .step = item.operation {
                for observation in tracked.observations where tracked.lead.observe(observation) { state.learned = id }
                tracked.observations = []
                state.windows[id] = tracked
            }
            return Prepared(lead: tracked.lead, previous: tracked.lastSize, animating: tracked.animating)
        }
        guard let prepared else { return }
        var stepFrame = CGRect.null
        if case let .step(step, frameAt) = item.operation {
            func plan(_ order: WindowLead.Order? = nil) -> WindowLead.Plan {
                prepared.lead.plan(at: began, presentation: step.presentation, period: step.period, order: order)
            }
            let first = plan()
            stepFrame = frameAt(first.times)
            let order = Self.order(window, stepFrame, previous: prepared.previous)
            let planned = order == first.order ? first : plan(order)
            if order != first.order { stepFrame = frameAt(planned.times) }
            state.withLock { $0.windows[id]?.lead.commit(planned) }
            guard window.cachedFrame != stepFrame else { return }
        }
        if window.placementSuspended || backend.blocksPlacement(window) {
            return refuse(item, wasAnimating: prepared.animating)
        }
        if !prepared.animating { enhancedUI.suspend() }
        write(item, stepFrame: stepFrame, previous: prepared.previous)
    }

    private func write(_ item: Pending, stepFrame: CGRect, previous: CGSize?) {
        let window = item.window, id = window.id
        switch item.operation {
        case .step:
            state.withLock { $0.windows[id]?.animating = true }
            record(id, stepFrame, write(window, stepFrame, previous: previous), learns: true)
        case let .follow(frame, done):
            let resized = previous != frame.size
            state.withLock { $0.windows[id]?.animating = true }
            record(id, frame, write(window, frame, previous: previous))
            let actual = resized ? window.frame.size : nil
            DispatchQueue.main.async { done(actual) }
        case let .position(point, done):
            let written = Write(position: attempt(point) { window.setPosition(point) })
            record(id, CGRect(origin: point, size: .zero), written)
            state.withLock { $0.windows[id]?.animating = false }
            enhancedUI.resume()
            DispatchQueue.main.async { done(written.applied) }
        case let .land(frame, done):
            let written = write(window, frame, previous: previous)
            record(id, frame, written, counts: false)
            state.withLock { state in
                state.windows[id]?.lastSize = nil
                state.windows[id]?.animating = false
                state.stats.land.add(written.seconds)
            }
            enhancedUI.resume()
            DispatchQueue.main.async { done(written.applied) }
        }
    }
}

extension AXWriter {
    private func attempt(_ value: CGPoint, _ write: () -> Bool) -> Attempt {
        let start = now()
        let applied = write()
        let finished = now()
        return Attempt(call: WindowLead.Call(value, seconds: finished - start, finished: finished), applied: applied)
    }

    private static func order(_ window: Window, _ frame: CGRect, previous: CGSize?) -> WindowLead.Order {
        guard previous != frame.size || window.cachedFrame.size != frame.size else { return .positionOnly }
        return switch WindowFrameOrder(from: window.cachedFrame, to: frame) {
        case .positionFirst: .positionFirst
        case .sizeFirst: .sizeFirst
        }
    }

    private func write(_ window: Window, _ frame: CGRect, previous: CGSize?) -> Write {
        var result = Write()
        func move() { result.position = attempt(frame.origin) { window.setPosition(frame.origin) } }
        func resize() {
            result.size = attempt(CGPoint(x: frame.width, y: frame.height)) { window.setSize(frame.size) }
        }
        switch Self.order(window, frame, previous: previous) {
        case .positionOnly: move()
        case .positionFirst: move(); resize()
        case .sizeFirst: resize(); move()
        }
        return result
    }

    private func record(_ id: CGWindowID, _ frame: CGRect, _ written: Write, learns: Bool = false,
                        counts: Bool = true) {
        state.withLock { state in
            state.windows[id]?.lead.wrote(position: written.position.flatMap { $0.applied ? $0.call : nil },
                                          size: written.size.flatMap { $0.applied ? $0.call : nil },
                                          learns: learns && written.applied)
            if let size = written.size { state.windows[id]?.lastSize = size.applied ? frame.size : nil }
            guard counts else { return }
            if let size = written.size { state.stats.size.add(size.call.seconds) }
            state.stats.position.add(written.position?.call.seconds ?? 0)
        }
    }
}
