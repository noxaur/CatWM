import AppKit
import Foundation
import QuartzCore

@MainActor package final class Animator {
    private var items: [CGWindowID: Item] = [:]
    private var landing: [CGWindowID: Move] = [:]
    private var quietUntil: [CGWindowID: CFTimeInterval] = [:]
    private var following = FollowedMoves()
    private var writers: [pid_t: AXWriter] = [:]
    private var owners: [CGWindowID: pid_t] = [:]
    private var epochs: [CGWindowID: Int] = [:], epochCount = 0
    private let backend: any WindowBackend
    private let makeWriter: (pid_t) -> AXWriter
    package var windowPresentation: (any WindowPresentation)?
    private var clock: (any FrameClock)?
    private let makeClock: MakeClock, now: () -> CFTimeInterval
    package let motionRun: MotionRun
    package var onMinimumSize: ((CGWindowID, CGSize) -> Void)?
    package var onTopRefused: ((_ target: CGRect, _ actual: CGRect) -> Void)?
    package var onLanded: (() -> Void)?

    package init(backend: any WindowBackend = AXBackend.shared, makeWriter: ((pid_t) -> AXWriter)? = nil,
                 now: @escaping () -> CFTimeInterval = CACurrentMediaTime,
                 makeClock: @escaping MakeClock = Animator.displayLink) {
        self.backend = backend
        self.makeWriter = makeWriter ?? { AXWriter(pid: $0, backend: backend) }
        (self.now, self.makeClock) = (now, makeClock)
        motionRun = MotionRun { backend.serverFrame(of: $0) }
    }

    deinit {
        let clock = clock, presentation = windowPresentation
        DispatchQueue.main.async {
            clock?.stop()
            presentation?.close()
        }
    }

    package func isBusy(_ id: CGWindowID) -> Bool {
        isAnimating(id) || (quietUntil[id] ?? 0) > now()
    }

    package func isAnimating(_ id: CGWindowID) -> Bool {
        items[id] != nil || landing[id] != nil || following[id] != nil
    }

    package func destination(_ id: CGWindowID) -> CGRect? {
        items[id]?.move.target ?? landing[id]?.target ?? following[id]?.target
    }

    package func isMoving(_ id: CGWindowID, to frame: CGRect) -> Bool { destination(id) == frame }

    package func cancel(_ id: CGWindowID) {
        windowPresentation?.cancel(id)
        nextEpoch(for: id)
        following.remove(id)
        items[id] = nil
        landing[id] = nil
        guard let pid = owners[id] else { return }
        writers[pid]?.cancel(id)
    }

    package func quiet(_ id: CGWindowID) {
        quietUntil[id] = now() + MotionTiming.quietAfterWrite
    }

    package func animate(_ moves: [Move], duration: Double, curve: AnimationCurve = .easeOut, bounce: Double = 0) {
        animate(moves, spec: MotionSpec(duration: duration, curve: curve, bounce: bounce))
    }
    package func animate(_ moves: [Move], spec: MotionSpec) { animate([Batch(moves: moves, spec: spec)]) }

    package func animate(_ batches: [Batch]) {
        let batches = batches.filter { !$0.moves.isEmpty }
        guard !batches.isEmpty else { return }
        let now = now()
        for batch in batches { batch.moves.forEach { start($0, spec: batch.spec, at: now) } }
        for batch in batches { windowPresentation?.prepare(batch.moves, spec: batch.spec) }
        startClock()
    }

    private func start(_ move: Move, spec: MotionSpec, at now: CFTimeInterval) {
        let id = move.window.id
        let from: CGRect
        var velocity: [Double]?
        if let running = items[id] {
            from = running.frame(at: now)
            velocity = running.velocity(at: now)
        } else if let landed = landing.removeValue(forKey: id) {
            from = move.from ?? landed.target
        } else if let followed = following[id] {
            from = move.from ?? followed.target
        } else {
            from = move.from ?? move.window.cachedFrame
        }
        cancel(id)
        owners[id] = move.window.pid
        if spec.duration < MotionTiming.landsAtOnceBelow || from.isNull
            || from.approxEqual(move.target, tolerance: FrameTolerance.landed) {
            land(move)
        } else {
            items[id] = Item(move: move, from: from, start: now, spec: spec, velocity: velocity)
            items[id]?.colorSizing = windowPresentation?.sizing(for: move, from: from, spec: spec)
        }
    }

    package func endFollow() { following.removeAll().forEach(land) }

    package func position(_ window: Window, at frame: CGRect) {
        cancel(window.id)
        owners[window.id] = window.pid
        let epoch = epochs[window.id]
        landing[window.id] = .init(window: window, to: frame, bounds: frame)
        quiet(window.id)
        writer(window.pid).position(window, at: frame.origin) { [weak self] _ in
            guard let self, self.epochs[window.id] == epoch else { return }
            self.landing[window.id] = nil
            self.quiet(window.id)
        }
    }

    package var activeWriterPids: Set<pid_t> { Set(writers.keys) }

    package func afterPendingWrites(pids: Set<pid_t>? = nil, _ completion: @escaping @MainActor @Sendable () -> Void) {
        afterPendingWrites(pids: pids, completionQueue: .main) { onMainThread { completion() } }
    }

    package func afterPendingWrites(
        pids: Set<pid_t>?, completionQueue: DispatchQueue, _ completion: @escaping @Sendable () -> Void
    ) {
        let selected = pids.map { ids in ids.compactMap { writers[$0] } } ?? Array(writers.values)
        guard !selected.isEmpty else {
            completionQueue.async(execute: completion)
            return
        }
        let group = DispatchGroup()
        for writer in selected {
            group.enter()
            writer.run { group.leave() }
        }
        group.notify(queue: completionQueue, execute: completion)
    }

    private func tick(shown: CFTimeInterval, presentation: CFTimeInterval) {
        motionRun.measure(items, at: shown, shown: windowPresentation)
        let started = CACurrentMediaTime(), moving = !items.isEmpty
        if moving { motionRun.tick(at: now()) }
        let ordered = items.sorted {
            let left = $0.value.colorSizing?.releasesSpace == true
            let right = $1.value.colorSizing?.releasesSpace == true
            return left == right ? $0.key < $1.key : left
        }
        for (id, item) in ordered {
            if presentation - item.start >= item.duration {
                items[id] = nil
                motionRun.finished(item)
                land(item.move)
            } else {
                writer(item.move.window.pid).step(item.move.window, notBefore: presentation,
                                                  releasesSpace: item.colorSizing?.releasesSpace == true) {
                    item.request(at: $0, presentedAt: presentation)
                }
            }
        }
        updateWindowPresentation(at: presentation)
        if moving { motionRun.ticked(CACurrentMediaTime() - started) }
        if items.isEmpty && !motionRun.isSettling {
            clock?.stop(); clock = nil
            motionRun.end(writers.map { ($0.key, $0.value.takeStats()) })
        }
    }

    private func land(_ move: Move) {
        let id = move.window.id
        let epoch = epochs[id] ?? nextEpoch(for: id)
        landing[id] = move
        quiet(id)
        writer(move.window.pid).land(move.window, at: move.target) { [weak self] wrote in
            guard let self, self.epochs[id] == epoch else { return }
            self.landing[id] = nil
            self.updateWindowPresentation()
            if wrote { self.onLanded?() }
            self.quiet(id)
            DispatchQueue.main.asyncAfter( // style-ok: an app that ignores a write sends no event
                deadline: .now() + MotionTiming.landingCheckDelay
            ) { [weak self] in self?.checkLanding(move, epoch: epoch) }
        }
    }

    private func checkLanding(_ move: Move, epoch: Int) {
        let id = move.window.id
        guard epochs[id] == epoch, items[id] == nil, landing[id] == nil, !move.window.placementSuspended else { return }
        quiet(id)
        let writer = writer(move.window.pid)
        writer.run(for: id) { [weak self, backend] isCurrent in
            guard let refusal = LandingCheck.run(move, writer: writer, backend: backend, isCurrent: isCurrent) else {
                return
            }
            DispatchQueue.main.async {
                guard let self, self.epochs[id] == epoch else { return }
                self.quiet(id)
                if let minimum = refusal.minimum { self.onMinimumSize?(id, minimum) }
                if refusal.refusedTop { self.onTopRefused?(move.target, refusal.actual) }
            }
        }
    }
}

extension Animator {
    package func follow(_ moves: [Move]) {
        for move in moves {
            let id = move.window.id
            if items[id] != nil || landing[id] != nil { cancel(id) }
            owners[id] = move.window.pid
            following.add(move)
            quiet(id)
        }
        windowPresentation?.follow(moves)
        updateWindowPresentation()
        for move in moves {
            writer(move.window.pid).follow(move.window, to: move.target) { [weak self] actual in
                guard let self else { return }
                self.updateWindowPresentation()
                guard let minimum = self.following.minimum(after: move, actual: actual) else { return }
                self.onMinimumSize?(move.window.id, minimum)
            }
        }
    }

    private func updateWindowPresentation(at time: CFTimeInterval? = nil) {
        guard let windowPresentation else { return }
        let time = time ?? now()
        let samples = items.mapValues { $0.frame(at: time, aligned: false) }
        let moving = following.frames.merging(samples) { _, frame in frame }
        windowPresentation.update(moving.merging(landing.mapValues(\.target)) { frame, _ in frame })
    }

    private func startClock() {
        guard !items.isEmpty else { return }
        let screens = backend.screens().filter { screen in
            items.values.contains { $0.move.target.intersects(screen.frame) }
        }.compactMap(\.nsScreen)
        let screen = screens.max(by: { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond }) ?? NSScreen.main
        guard clock == nil || clock?.displayID != screen?.displayID else { return }
        guard let next = makeClock(screen, { [weak self] in self?.tick(shown: $0, presentation: $1) }) else {
            let unfinished = Array(items.values)
            items.removeAll()
            unfinished.forEach { land($0.move) }
            return
        }
        if clock == nil { motionRun.begin("window-move") }
        clock?.stop(); clock = next
    }

    private func writer(_ pid: pid_t) -> AXWriter {
        if let existing = writers[pid] { return existing }
        let created = makeWriter(pid)
        writers[pid] = created
        return created
    }

    package func forget(_ id: CGWindowID) {
        cancel(id)
        if let pid = owners.removeValue(forKey: id) { writers[pid]?.forget(id) }
        epochs[id] = nil
        quietUntil[id] = nil
    }

    @discardableResult
    private func nextEpoch(for id: CGWindowID) -> Int {
        epochCount += 1
        epochs[id] = epochCount
        return epochCount
    }

    package func terminated(_ pid: pid_t) { writers[pid] = nil }
}

extension Animator {
    package func retarget(_ window: Window, to frame: CGRect) -> Bool {
        guard let running = items[window.id] else { return false }
        let target = [frame.minX, frame.minY, frame.width, frame.height]
        let tracks = zip(running.tracks, target).map { $0.retargeted(to: $1) }
        items[window.id] = Item(move: .init(window: window, to: frame, bounds: frame), tracks: tracks,
                                start: running.start, duration: running.duration)
        if let sizing = running.colorSizing, frame.minY == sizing.source.minY {
            items[window.id]?.colorSizing = ColorFillSizing(source: sizing.source, target: frame)
        }
        return true
    }
}
