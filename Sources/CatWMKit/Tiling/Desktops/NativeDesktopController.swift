import AppKit
import QuartzCore

@MainActor package final class NativeDesktopController {
    package typealias Request = DesktopMachine.Request
    package typealias Switch = DesktopMachine.Switch
    package typealias Settings = MotionSpec
    package var settings = MotionSpec(duration: 0.18, curve: .easeOut, bounce: 0.5)
    package var motionSpec: (Switch) -> MotionSpec? = { _ in nil }
    package var prepare: (Request) async throws -> Void = { _ in }
    package var onSettled: (Switch, _ changed: Bool) -> Void = { _, _ in }
    package var onMotion: (Request) -> Void = { _ in }
    package var isForward: (_ source: UInt64, _ target: UInt64, _ desktopOrder: Bool) -> Bool = { $2 }
    package var onIdle: () -> Void = {}
    package var onFailure: (String) -> Void = { _ in }
    package var guarded = true
    package private(set) var machine = DesktopMachine()
    private var waiters: [Int: CheckedContinuation<Void, Error>] = [:]
    private var jobs = 0
    private var finishingSlide = false
    private var nextSlide: Switch?
    private var moves: [Int: () -> Void] = [:]
    private var nextMove = 0
    private var requestedAt: CFTimeInterval = 0
    private var timing: DesktopTransitionTiming?
    private var warmGuard: DesktopGuardClient?

    package var requested: Request? { machine.wanted?.request }
    package var isRunning: Bool { machine.slide != nil }
    package var isBusy: Bool { !machine.isIdle }
    package var isLocked: Bool { machine.held != nil }
    package var isTracking: Bool { machine.isTracking }

    package func request(_ target: Switch, since start: CFTimeInterval = CACurrentMediaTime()) {
        requestedAt = start
        send(.request(target))
    }

    package func beginGesture(_ target: Switch, direction: Double) {
        requestedAt = CACurrentMediaTime()
        send(.beginGesture(target, direction: direction))
    }

    package func scrub(_ value: Double) { send(.scrub(value)) }

    package func endGesture(commit: Bool) { send(.endGesture(commit: commit)) }

    package func stop() { send(.stop) }

    private func transition(_ target: Request, since start: CFTimeInterval) async throws {
        let timing = DesktopTransitionTiming(since: start)
        self.timing = timing; timing.checkpoint("queue")
        guard let screen = Screen.all().first(where: { $0.uuid == target.display }) else {
            throw DesktopTransitionError.check("The display disconnected")
        }
        let source = Spaces.current(display: target.display)
        Log.info("native workspaces: \(source) → \(target.space), workspace \(target.workspace)")
        if source == target.space { settled(target, changed: false); return }
        let busy = "Finish the current macOS Desktop action, then try again"
        var list: Spaces.DisplaySpaces?, sourceState: DesktopBridge.State?, targetState: DesktopBridge.State?
        let ready = await poll(1, every: 10_000_000) {
            list = Spaces.list(display: target.display)
            sourceState = DesktopBridge.state(source)
            targetState = DesktopBridge.state(target.space)
            return DesktopUI.isSettled(screen) && sourceState?.transform == .identity
                && targetState?.transform == .identity
                && list.map { $0.ids.contains(source) && $0.ids.contains(target.space) } == true
        }
        guard ready, let list, let from = list.ids.firstIndex(of: source),
              let into = list.ids.firstIndex(of: target.space), let sourceState, let targetState else {
            throw DesktopTransitionError.check(busy)
        }
        let state = DesktopGuard.Context(display: target.display, source: source, destination: target.space,
                                         sourceOptions: sourceState.options, destinationOptions: targetState.options)
        let recovery = acquireGuard()
        timing.checkpoint("ready")
        try await prepareWhileGuarding(target, state, recovery)
        timing.checkpoint("guard/layout")
        if !wants(target) { try await release(recovery); return }
        var failure: Error?
        do {
            try await compose(state, screen: screen, forward: into > from, target: target, recovery: recovery)
        } catch { failure = error }
        state.restore(); try await recovery.restore()
        let restored = await poll(1) {
            DesktopBridge.isIdentity(source) && DesktopBridge.isIdentity(target.space)
                && DesktopBridge.isIdle(display: target.display)
        }
        guard restored else { throw DesktopTransitionError.check("Desktop recovery is still in progress") }
        try await release(recovery)
        if let failure {
            let maximised = !list.desktops.contains(from) || !list.desktops.contains(into)
            guard maximised, wants(target), Spaces.current(display: target.display) != target.space else {
                throw failure
            }
            Log.info("native workspaces: \(failure.localizedDescription); swiping to the maximised window")
            try await swipe(to: target)
        }
        Log.info("native workspaces: restored transforms after \(target.workspace)")
        if Spaces.current(display: target.display) == target.space { settled(target, changed: true) }
    }

    private func prepareWhileGuarding(_ target: Request, _ state: DesktopGuard.Context,
                                      _ recovery: DesktopGuardClient) async throws {
        let launch = Task { @MainActor in try await recovery.start(state) }
        var preparation: Error?
        do { try await prepare(target) } catch { preparation = error }
        do { try await launch.value } catch { throw preparation ?? error }
        if let preparation { try? await release(recovery); throw preparation }
    }

    private func compose(_ state: DesktopGuard.Context, screen: Screen, forward desktopOrder: Bool,
                         target: Request, recovery: DesktopGuardClient) async throws {
        let fresh = DesktopMenuBar.isFresh(state.destination)
        DesktopWallpaperCover.shared.prepare(on: screen, source: state.source, target: state.destination, fresh: fresh)
        let forward = isForward(state.source, state.destination, desktopOrder)
        let width = screen.frame.width * (forward ? 1 : -1)
        var progress = 0.0
        try check(DesktopBridge.animating(display: state.display, active: true), "Cannot begin Desktop motion")
        try apply(state, width: width, progress: 0)
        try check(DesktopBridge.willSwitch([state.destination]), "Cannot prepare the destination Desktop")
        try check(DesktopBridge.setVisible([state.destination], true), "Cannot show the destination Desktop")
        onMotion(target)
        let motion = DesktopMotion(screen: screen.nsScreen)
        let covered = DesktopWallpaperCover.shared.isReady(source: state.source, target: state.destination)
        async let drawn: Void = fresh && !covered ? motion.frames(2) : ()
        let menu = try await prepareMenuBar(state, on: screen, recovery: recovery)
        self.timing?.checkpoint("menu")
        defer { menu?.restore() }
        guard wants(target) else { return }
        try await drawn
        let wallpaper = await DesktopWallpaperCover.shared.present(
            source: state.source, target: state.destination, while: { self.wants(target) })
        defer { wallpaper?.end(shown: Spaces.current(display: state.display) == state.destination, settings: settings) }
        guard wants(target) else { return }
        try checkCurrentSource(state)
        self.timing?.checkpoint("show/frames")
        if machine.isTracking {
            try await motion.follow(until: { !self.machine.isTracking }, update: {
                try self.check(recovery.process.isRunning, "Desktop recovery process stopped")
                progress = self.machine.progress
                try self.apply(state, width: width, progress: progress)
                return progress
            })
        }
        while true {
            let landing = wants(target) ? 1.0 : 0.0
            do {
                try await motion.animate(from: progress, to: landing, with: settings) { value in
                    guard (self.wants(target) ? 1.0 : 0.0) == landing else { throw Retarget.changed }
                    try self.check(recovery.process.isRunning, "Desktop recovery process stopped")
                    progress = value
                    try self.apply(state, width: width, progress: value)
                }
                break
            } catch Retarget.changed { continue }
        }
        try checkCurrentSource(state)
        if wants(target) {
            try await activate(state, menu: menu, wallpaper: wallpaper, screen: screen, target: target)
        }
    }

    private func activate(_ state: DesktopGuard.Context, menu: DesktopMenuBarLease?,
                          wallpaper: DesktopWallpaperCover.Lease?,
                          screen: Screen, target: Request) async throws {
        let batch = WindowServerUpdates.shared.begin()
        if let menu, DesktopMenuBarNative.theme(state.destination) == menu.state.theme { menu.restore() }
        try check(DesktopBridge.setVisible([state.source], false), "Cannot hide the source Desktop")
        try check(DesktopBridge.setCurrent(display: state.display, space: state.destination),
                  "Cannot activate the destination Desktop")
        batch?.finish()
        let arrived = await poll(1) { Spaces.current(display: state.display) == state.destination }
        try check(arrived, "macOS did not activate the destination Desktop")
        wallpaper?.end(shown: true, settings: settings)
        DesktopMenuBar.shown(state.destination)
        try await DesktopMenuBar.settle(menu?.state, on: screen, while: { self.wants(target) })
        await menu?.finish()
    }

    private func prepareMenuBar(_ state: DesktopGuard.Context, on screen: Screen,
                                recovery: DesktopGuardClient) async throws -> DesktopMenuBarLease? {
        guard DesktopMenuBar.needsPreparation(source: state.source, target: state.destination) else { return nil }
        let cover = DesktopMenuBarCover.shared
        let image = Task { await cover.capture(on: screen, source: state.source, target: state.destination) }
        let background = await DesktopMenuBar.ready(source: state.source, target: state.destination, screen: screen)
        timing?.checkpoint("menu-ready")
        guard let background else { DesktopMenuBarCover.shared.recycle(await image.value); return nil }
        do {
            try background.persist()
            var guarded = state
            guarded.menuBar = background
            try await recovery.update(guarded)
            guard DesktopBridge.detachMenuWindows([background.window], from: background.space),
                  await poll(0.1, every: 250_000, until: { Spaces.of(window: background.window).isEmpty }) else {
                throw DesktopTransitionError.check("Cannot prepare the Desktop background")
            }
        } catch {
            background.restore(); DesktopMenuBarCover.shared.recycle(await image.value)
            throw error
        }
        timing?.checkpoint("menu-guard")
        let panel = await image.value
        timing?.checkpoint("menu-cover")
        if panel == nil {
            Log.info("native workspaces: no menu bar cover, screen recording "
                        + "\(PermissionWatcher.shared.granted.contains(.screenRecording))")
        }
        _ = DesktopMenuBarNative.alpha(background.space, 0)
        return DesktopMenuBarLease(state: background, panel: panel)
    }

    private enum Retarget: Error { case changed }

    private func swipe(to target: Request) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        func remaining() -> TimeInterval { deadline - ProcessInfo.processInfo.systemUptime }
        while Spaces.current(display: target.display) != target.space {
            if !wants(target) { return }
            guard remaining() > 0,
                  let list = Spaces.list(display: target.display), let current = list.current,
                  let destination = list.ids.firstIndex(of: target.space) else {
                throw DesktopTransitionError.check("macOS did not reach the Desktop")
            }
            let source = list.ids[current]
            try check(DesktopSwipe.post(right: destination > current), "Native Desktop navigation is unavailable")
            try await check(poll(remaining(), every: 20_000_000) { Spaces.current(display: target.display) != source },
                            "macOS did not change Desktop")
            try await check(poll(remaining(), every: 20_000_000) { DesktopBridge.isIdle(display: target.display) },
                            "macOS did not finish changing Desktop")
        }
    }
}

extension NativeDesktopController {
    private func apply(_ state: DesktopGuard.Context, width: CGFloat, progress: Double) throws {
        let pose = min(1, max(0, progress))
        if pose > 0 { timing?.motion() }
        try check(DesktopBridge.transform(state.destination, x: (pose - 1) * width,
                                          options: state.destinationOptions), "Cannot move the destination Desktop")
        try check(DesktopBridge.transform(state.source, x: pose * width, options: state.sourceOptions),
                  "Cannot move the source Desktop")
    }

    private func wants(_ target: Request) -> Bool { machine.wants(target) }

    private func checkCurrentSource(_ state: DesktopGuard.Context) throws {
        try check(Spaces.current(display: state.display) == state.source,
                  "Native navigation interrupted Desktop switching")
    }

    private func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw DesktopTransitionError.check(message) }
    }

    package func prewarmGuard() {
        guard guarded else { return }
        DesktopWallpaperCover.shared.prepare()
        guard warmGuard?.process.isRunning != true else { return }
        let client = DesktopGuardClient()
        if (try? client.launch()) != nil { warmGuard = client }
    }

    private func acquireGuard() -> DesktopGuardClient {
        defer { warmGuard = nil }
        if let warmGuard, warmGuard.process.isRunning { return warmGuard }
        return DesktopGuardClient()
    }

    private func release(_ recovery: DesktopGuardClient) async throws {
        try await recovery.release()
        if warmGuard?.process.isRunning != true {
            warmGuard = recovery
        } else if warmGuard !== recovery {
            try await recovery.shutDown()
        }
    }
}

extension NativeDesktopController {
    @MainActor func swipeUnguarded(to target: Request) async throws {
        let changed = Spaces.current(display: target.display) != target.space
        try await swipe(to: target)
        if Spaces.current(display: target.display) == target.space { settled(target, changed: changed) }
    }
}

extension NativeDesktopController {
    package func cancelCreation(for window: CGWindowID) { send(.cancelWindow(window)) }

    package func move(window: CGWindowID, to space: UInt64, waitUntilOnScreen: Bool = false,
                      completion: @escaping @MainActor (Bool) -> Void) {
        let id = nextMove
        nextMove += 1
        moves[id] = { [weak self] in
            Spaces.move(window: window, to: space, waitUntilOnScreen: waitUntilOnScreen) { moved in
                self?.send(.moveEnded(id))
                completion(moved)
            }
        }
        send(.moveRequested(id))
    }

    package func move(window: CGWindowID, to space: UInt64) async -> Bool {
        await withCheckedContinuation { done in move(window: window, to: space) { done.resume(returning: $0) } }
    }

    package func reserve(_ work: DesktopMachine.Work) -> Int {
        let id = jobs
        jobs += 1
        send(.enqueue(.init(id: id, work: work)))
        return id
    }

    package func exclusively<Result>(_ work: DesktopMachine.Work, report: (Result) -> Request? = { _ in nil },
                                     _ body: () async throws -> Result) async throws -> Result {
        try await exclusively(reserve(work), report: report, body)
    }

    package func exclusively<Result>(_ id: Int, report: (Result) -> Request? = { _ in nil },
                                     _ body: () async throws -> Result) async throws -> Result {
        if machine.held?.job.id != id {
            guard machine.queue.contains(where: { $0.id == id }) else { throw CancellationError() }
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { waiters[id] = $0 }
            } onCancel: {
                Task { @MainActor in self.send(.cancel(job: id)) }
            }
        }
        let result: Result
        do { result = try await body() } catch {
            send(.finished(job: id, nil))
            throw error
        }
        let current = machine.held?.current == true
        send(.finished(job: id, report(result)))
        guard current else { throw CancellationError() }
        return result
    }

    private func send(_ event: DesktopMachine.Event) {
        for effect in machine.send(event) {
            switch effect {
            case .slide(let target):
                if finishingSlide {
                    nextSlide = target
                } else {
                    Task { @MainActor in await self.slide(from: target) }
                }
            case .grant(let id): waiters.removeValue(forKey: id)?.resume()
            case .drop(let id): waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
            case .startMove(let id): moves.removeValue(forKey: id)?()
            case .idle: onIdle()
            }
        }
    }

    private func slide(from first: Switch) async {
        var next: Switch? = first
        while let target = next {
            await run(target)
            finishingSlide = true
            send(.slideFinished)
            finishingSlide = false
            next = nextSlide
            nextSlide = nil
        }
    }

    private func run(_ target: Switch) async {
        settings = motionSpec(target) ?? settings
        do {
            if guarded {
                try await transition(target.request, since: requestedAt)
            } else {
                try await swipeUnguarded(to: target.request)
            }
        } catch {
            onFailure(error.localizedDescription)
        }
    }

    private func settled(_ target: Request, changed: Bool) {
        let current = machine.slide?.target
        onSettled(current.flatMap { $0.request == target ? $0 : nil } ?? Switch(request: target), changed)
    }
}
