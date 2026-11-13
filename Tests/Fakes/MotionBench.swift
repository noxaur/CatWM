import AppKit
import CatWMKit
import os

package struct AppLatency: Sendable {
    package let name: String
    package var position = 0.0, size = 0.0, moved = 0.0, resized = 0.0, jitter = 0.0

    package static let instant = AppLatency(name: "instant")
    package static let fixed = AppLatency(name: "fixed", position: 0.001, size: 0.004, moved: 0.024, resized: 0.024)
    package static let jittery = AppLatency(name: "jitter", position: 0.001, size: 0.004, moved: 0.024, resized: 0.024,
                                            jitter: 0.016)
    package static let slowResize = AppLatency(name: "slow-resize", position: 0.0005, size: 0.012, moved: 0.004,
                                               resized: 0.05)
    package static let profiles = [fixed, jittery, slowResize]
}

package final class LatencyBackend: WindowBackend, Sendable {
    private struct Shown { var time: Double, origin: CGPoint?, size: CGSize? }
    private struct State {
        var time = 1.0
        var clocks: [pid_t: Double] = [:]
        var base: [CGWindowID: CGRect] = [:]
        var shown: [CGWindowID: [Shown]] = [:]
        var seed: UInt64 = 0x5EED
    }
    package let inner = FakeBackend()
    package let latency: AppLatency
    private let state = OSAllocatedUnfairLock(initialState: State())

    package init(_ latency: AppLatency) { self.latency = latency }

    package var time: Double { state.withLock { $0.time } }
    package func advance(to time: Double) { state.withLock { $0.time = time } }
    package func clock(_ pid: pid_t) -> Double { state.withLock { $0.clocks[pid] ?? $0.time } }
    package func catchUp(_ pid: pid_t) { state.withLock { $0.clocks[pid] = max($0.clocks[pid] ?? 0, $0.time) } }

    package func addWindow(pid: pid_t, frame: CGRect) -> CGWindowID {
        let id = inner.addWindow(pid: pid, frame: frame)
        state.withLock { $0.base[id] = frame }
        return id
    }

    package func lastShown(_ id: CGWindowID) -> Double? { state.withLock { $0.shown[id]?.last?.time } }

    package func shownFrame(_ id: CGWindowID) -> CGRect? {
        state.withLock { state in
            guard var frame = state.base[id] else { return nil }
            for shown in state.shown[id] ?? [] where shown.time <= state.time {
                if let origin = shown.origin { frame.origin = origin }
                if let size = shown.size { frame.size = size }
            }
            return frame
        }
    }

    private func spend(_ window: Window, cost: Double, delay: Double, origin: CGPoint?, size: CGSize?) {
        state.withLock { state in
            func noise() -> Double {
                state.seed = state.seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(state.seed >> 11) / Double(1 << 53) * 2 - 1
            }
            let clock = (state.clocks[window.pid] ?? state.time) + cost * (1 + noise() * min(1, latency.jitter * 30))
            state.clocks[window.pid] = clock
            let previous = state.shown[window.id]?.last { (origin == nil) == ($0.origin == nil) }?.time ?? 0
            let time = max(previous, clock + max(0, delay + noise() * latency.jitter))
            state.shown[window.id, default: []].append(Shown(time: time, origin: origin, size: size))
            state.shown[window.id]?.sort { $0.time < $1.time }
        }
    }

    package func setPosition(_ window: Window, _ point: CGPoint) -> Bool {
        guard inner.setPosition(window, point) else { return false }
        spend(window, cost: latency.position, delay: latency.moved, origin: point, size: nil)
        return true
    }

    package func setSize(_ window: Window, _ size: CGSize) -> Bool {
        guard inner.setSize(window, size) else { return false }
        spend(window, cost: latency.size, delay: latency.resized, origin: nil, size: inner.frame(of: window.id).size)
        return true
    }

    package func applications() -> [RunningApplicationSnapshot] { inner.applications() }
    package func desktop(known: Set<CGWindowID>) -> WindowServerObservation { inner.desktop(known: known) }
    package func scan(_ job: WindowScanner.Job,
                      discovered: (WindowScanner.AppScan) -> Void) -> WindowScanner.AppScan {
        inner.scan(job, discovered: discovered)
    }
    package func focusedWindow(pid: pid_t) -> FocusReader.Result { inner.focusedWindow(pid: pid) }
    package func screens() -> [Screen] { inner.screens() }
    package func currentSpace(display: String) -> UInt64 { inner.currentSpace(display: display) }
    package func isRunning(_ pid: pid_t) -> Bool { inner.isRunning(pid) }
    package func frontmostPID() -> pid_t? { inner.frontmostPID() }
    package func frame(of window: Window) -> CGRect { inner.frame(of: window) }
    package func blocksPlacement(_ window: Window) -> Bool { inner.blocksPlacement(window) }
    package func suspendEnhancedUI(_ pid: pid_t) -> Bool { inner.suspendEnhancedUI(pid) }
    package func resumeEnhancedUI(_ pid: pid_t) { inner.resumeEnhancedUI(pid) }
    package func focus(_ window: Window, ifCurrent: () -> Bool) { inner.focus(window, ifCurrent: ifCurrent) }
    package func refreshCursor() { inner.refreshCursor() }
    package func close(_ window: Window) -> String { inner.close(window) }
}

@MainActor package final class MotionBench {
    package enum Mode: String, CaseIterable { case live, colorFill = "color-fill" }
    package struct Result {
        package let quality: MotionQuality.Summary?
        package let ticks: Stat
        package let settle: Double
    }
    private final class Clock: FrameClock {
        let displayID: CGDirectDisplayID?
        let tick: Animator.Tick
        var running = true
        init(_ displayID: CGDirectDisplayID?, _ tick: @escaping Animator.Tick) {
            self.displayID = displayID
            self.tick = tick
        }
        func stop() { running = false }
    }
    private final class Gate: Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        let writer: AXWriter
        init(_ writer: AXWriter) { self.writer = writer; hold() }
        func hold() { let semaphore = semaphore; writer.run { semaphore.wait() } }
        func release(hold again: Bool = true) async {
            semaphore.signal()
            await withCheckedContinuation { done in writer.run { done.resume() } }
            if again { hold() }
        }
    }

    package static let frame = 1.0 / 60
    package let backend: LatencyBackend
    package let animator: Animator
    private var gates: [pid_t: Gate] = [:]
    private var clock: Clock?
    private var ended: (ticks: Stat, quality: MotionQuality?)?
    private var ids: [CGWindowID] = []
    private let fills: Fills?

    package init(_ latency: AppLatency, mode: Mode) {
        let backend = LatencyBackend(latency)
        backend.inner.addScreen()
        self.backend = backend
        fills = mode == .colorFill ? Fills(read: backend.shownFrame) : nil
        var made: ((pid_t, AXWriter) -> Void)?
        var started: ((Clock) -> Void)?
        animator = Animator(backend: backend, makeWriter: { pid in
            let writer = AXWriter(pid: pid, backend: backend, now: { backend.clock(pid) })
            made?(pid, writer)
            return writer
        }, applyFocus: { _, _ in }, now: { backend.time }, makeClock: { screen, tick in
            let clock = Clock(screen?.displayID, tick)
            started?(clock)
            return clock
        })
        made = { [unowned self] pid, writer in gates[pid] = Gate(writer) }
        started = { [unowned self] in clock = $0 }
        animator.motionRun.measures = true
        animator.motionRun.readFrame = backend.shownFrame
        animator.windowPresentation = fills
        animator.motionRun.onEnd = { [unowned self] ticks, quality in ended = (ticks, quality) }
    }

    package func window(pid: pid_t, frame: CGRect) -> Window {
        let id = backend.addWindow(pid: pid, frame: frame)
        guard let element = backend.inner.element(id) else { preconditionFailure("the fake window has no element") }
        let window = Window(id: id, element: element, pid: pid, bundleID: nil, backend: backend)
        window.remember(frame)
        fills?.add(id, size: frame.size)
        ids.append(id)
        return window
    }

    package func run(_ moves: [Animator.Move], spec: MotionSpec = MotionSpec(Config())) async -> Result? {
        ended = nil
        animator.animate(moves, spec: spec)
        var frames = 0, time = backend.time - Self.frame / 2
        while let clock, clock.running, frames < 600 {
            frames += 1
            time += Self.frame
            backend.advance(to: time)
            clock.tick(time, time + Self.frame)
            for (pid, gate) in gates.sorted(by: { $0.key > $1.key }) where backend.clock(pid) <= time {
                backend.catchUp(pid)
                await gate.release()
            }
        }
        let end = backend.time + Self.frame
        for (pid, gate) in gates.sorted(by: { $0.key > $1.key }) {
            backend.advance(to: max(backend.time, backend.clock(pid)))
            backend.catchUp(pid)
            await gate.release(hold: false)
        }
        gates = [:]
        clock = nil
        guard let ended else { return nil }
        let shown = ids.compactMap(backend.lastShown).max() ?? end
        return Result(quality: ended.quality?.summary(), ticks: ended.ticks, settle: max(0, shown - end))
    }

    @MainActor private final class Fills: WindowPresentation {
        private var appearances: [CGWindowID: WindowFillAppearance] = [:]
        private var active: Set<CGWindowID> = []
        private var filling: Set<CGWindowID> = []
        private let read: (CGWindowID) -> CGRect?

        init(read: @escaping (CGWindowID) -> CGRect?) { self.read = read }

        func add(_ id: CGWindowID, size: CGSize) {
            let width = Int(size.width), height = Int(size.height)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            appearances[id] = context.makeImage().flatMap { WindowFillAppearance(image: $0, size: size) }
        }

        func prepare(_ moves: [Animator.Move], spec: MotionSpec) {
            for move in moves {
                let id = move.window.id
                guard spec.duration >= 0.08, appearances[id]?.canFill(from: move.window.cachedFrame,
                                                                      to: move.target) == true else {
                    cancel(id); continue
                }
                active.insert(id)
            }
        }

        func sizing(for move: Animator.Move, from: CGRect, spec: MotionSpec) -> ColorFillSizing? {
            guard spec.duration >= 0.08, appearances[move.window.id]?.canFill(from: from, to: move.target) == true
            else { return nil }
            return ColorFillSizing(source: from, target: move.target)
        }

        func update(_ frames: [CGWindowID: CGRect]) {
            for id in active where frames[id] == nil { cancel(id) }
            filling = Set(active.filter { id in
                guard let desired = frames[id], let actual = read(id), let appearance = appearances[id] else {
                    return false
                }
                return WindowResizeFill.fits(desired: desired, actual: actual, minimumSize: appearance.minimumSize)
                    && WindowResizeFill.needed(desired: desired, actual: actual)
            })
        }

        func isFilling(_ id: CGWindowID) -> Bool { filling.contains(id) }
        func cancel(_ id: CGWindowID) { active.remove(id); filling.remove(id) }
        func close() { active.removeAll(); filling.removeAll() }
    }
}

extension MotionBench {
    package struct Scene {
        package let name: String
        package let windows: [(from: CGRect, to: CGRect)]
    }

    package static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    package static func ratio(rows: Int = 1) -> Scene {
        let height = screen.height / CGFloat(rows)
        let windows = (0..<rows).flatMap { row -> [(from: CGRect, to: CGRect)] in
            let top = CGFloat(row) * height
            return [(CGRect(x: 0, y: top, width: 720, height: height),
                     CGRect(x: 0, y: top, width: 864, height: height)),
                    (CGRect(x: 720, y: top, width: 720, height: height),
                     CGRect(x: 864, y: top, width: 576, height: height))]
        }
        return Scene(name: rows == 1 ? "ratio" : "ratio-\(rows * 2)", windows: windows)
    }

    package static let stackOpen = Scene(name: "stack-open", windows: [
        (CGRect(x: 720, y: 0, width: 720, height: 450), CGRect(x: 720, y: 0, width: 720, height: 300)),
        (CGRect(x: 720, y: 450, width: 720, height: 450), CGRect(x: 720, y: 300, width: 720, height: 300))
    ])

    package static let swap = Scene(name: "swap", windows: [
        (CGRect(x: 0, y: 0, width: 960, height: 900), CGRect(x: 960, y: 450, width: 480, height: 450)),
        (CGRect(x: 960, y: 450, width: 480, height: 450), CGRect(x: 0, y: 0, width: 960, height: 900))
    ])

    package static let moves = [ratio(), stackOpen, swap]

    package static func measure(_ scene: Scene, _ latency: AppLatency, mode: Mode) async -> Result? {
        let bench = MotionBench(latency, mode: mode)
        let moves = scene.windows.enumerated().map { index, frames in
            Animator.Move(window: bench.window(pid: pid_t(-100 - index), frame: frames.from), to: frames.to,
                          bounds: screen)
        }
        return await bench.run(moves)
    }
}
