import AppKit
import QuartzCore

extension WindowManager {
    @discardableResult
    package func goToSpace(_ number: Int, autoCorrect: Bool = true) -> Int? {
        let point = mouseLocation()
        let screen = backend.screens().first(where: { $0.frame.contains(point) }) ?? currentScreen()
        let info = screen.flatMap { backend.spaceList(display: $0.uuid) }
        if let combo = backend.desktopShortcut(number) {
            postKey(combo)
            if let screen, let info, info.desktops.indices.contains(number - 1) {
                _ = nativeDesktop.step(.init(display: screen.uuid, target: info.desktops[number - 1],
                                             until: Date().addingTimeInterval(0.6), corrections: 2))
            } else {
                nativeDesktop.endStep()
            }
            return 1
        }
        guard let screen, let info, var cur = info.current else {
            Log.info("spaces: can't read the space list")
            return nil
        }
        guard number >= 1, number <= info.desktops.count else {
            surface.showHUD("There is no space \(number)", on: screen.nsScreen)
            return nil
        }
        if let step = nativeDesktop.machine.step, step.goal.display == screen.uuid, Date() < step.goal.until {
            cur = step.goal.target
        }
        let target = info.desktops[number - 1]
        let delta = target - cur
        guard delta != 0 else { return 0 }
        guard let combo = backend.stepShortcut(right: delta > 0) else {
            surface.showHUD("Turn on “Move left/right a space” in Keyboard Shortcuts", on: screen.nsScreen)
            return nil
        }
        Log.info(
            "spaces: desktop \(cur + 1) → \(number), stepping \(delta) with key \(combo.keyCode) "
                + "flags \(combo.flags.rawValue) style \(keyPostStyle)"
        )
        for _ in 0..<abs(delta) { postKey(combo) }
        let settle = 0.6 + 0.15 * Double(abs(delta))
        let until = Date().addingTimeInterval(settle)
        let token = nativeDesktop.step(.init(display: screen.uuid, target: target, until: until, corrections: 2))
        guard autoCorrect else { return abs(delta) }
        DispatchQueue.main.asyncAfter( // style-ok: no event marks the last queued Desktop step
            deadline: .now() + settle
        ) { [weak self] in self?.correctSpace(token) }
        return abs(delta)
    }

    package func switchSpace(_ number: Int) { goToSpace(number) }

    package func correctSpace(_ token: Int) {
        guard let step = nativeDesktop.machine.step, step.token == token, step.goal.corrections > 0,
              let info = backend.spaceList(display: step.goal.display), let cur = info.current,
              cur != step.goal.target, let combo = backend.stepShortcut(right: step.goal.target > cur) else { return }
        let delta = step.goal.target - cur
        Log.info("spaces: landed on \(cur + 1) instead of \(step.goal.target + 1); correcting by \(delta)")
        for _ in 0..<abs(delta) { postKey(combo) }
        let settle = 0.6 + 0.15 * Double(abs(delta))
        nativeDesktop.corrected(token, until: Date().addingTimeInterval(settle))
        DispatchQueue.main.asyncAfter( // style-ok: no event marks the last queued Desktop step
            deadline: .now() + settle
        ) { [weak self] in self?.correctSpace(token) }
    }

    package func stepToSpace(_ space: UInt64, then arrived: @escaping @MainActor () -> Void) -> Bool {
        for screen in backend.screens() {
            guard let info = backend.spaceList(display: screen.uuid), let target = info.ids.firstIndex(of: space),
                  let cur = info.current, cur != target, let combo = backend.stepShortcut(right: target > cur)
            else { continue }
            let steps = abs(target - cur)
            let until = Date().addingTimeInterval(1 + 0.5 * Double(steps))
            let token = nativeDesktop.step(.init(display: screen.uuid, target: target, until: until, arrival: space))
            desktops.spaceArrival = (token, arrived)
            for _ in 0..<steps { postKey(combo) }
            return true
        }
        return false
    }

    package func activeSpaceChanged(at now: Date = Date()) {
        guard let step = nativeDesktop.machine.step, let space = step.goal.arrival,
              now > step.goal.until || backend.currentSpace(display: step.goal.display) == space else { return }
        nativeDesktop.endStep(step.token)
        guard let arrival = desktops.spaceArrival, arrival.token == step.token else { return }
        desktops.spaceArrival = nil
        if now <= step.goal.until { arrival.action() }
    }

    package func moveToSpace(_ number: Int) {
        guard !nativeDesktop.isGrabbing, let window = focusedWindow() else { return }
        let frame = window.frameUnlessStalled
        guard !frame.isNull else { return }
        let points = grabPoints(for: window, frame: frame)
        guard !points.isEmpty else {
            surface.showHUD("This window has nothing to grab", on: screen(of: window)?.nsScreen)
            Log.info("move to space: no grab point for \(window.bundleID ?? "pid \(window.pid)")")
            return
        }
        nativeDesktop.grab(true)
        focus(window, warp: false)
        tryGrab(window, points[...], space: number, restore: mouseLocation())
    }

    package func postKey(_ combo: SystemShortcut.Combo) {
        backend.post(keyCode: combo.keyCode, flags: combo.flags, style: keyPostStyle)
    }

    package func postMouse(_ type: CGEventType, _ point: CGPoint) {
        guard input.pointerAndFocus else { return }
        backend.postMouse(type, at: point)
    }

    package func handleNativeSwipe(_ sample: DesktopGestureTap.Sample) {
        if sample.phase == 1 { nativeDesktop.endGesture(commit: false) }
        if !nativeDesktop.isBusy, abs(sample.progress) > 0.001 {
            guard let screen = backend.screens().first(where: { $0.frame.contains(mouseLocation()) }) else { return }
            updateNativeCatalog(backend.screens())
            let space = backend.currentSpace(display: screen.uuid)
            guard let source = desktops.nativeCatalog.entry(space: space) else { return }
            let direction = sample.progress > 0 ? 1 : -1
            guard let name = desktops.nativeCatalog.step(from: source.name, by: direction),
                  let target = desktops.nativeCatalog.entry(name) else { return }
            let request = DesktopMachine.Request(workspace: name, display: target.display, space: target.space)
            nativeDesktop.beginGesture(.init(request: request, options: .init(motion: currentWorkspace)),
                                       direction: Double(direction))
        }
        guard nativeDesktop.isTracking, let direction = nativeDesktop.machine.slide?.gesture?.direction else { return }
        nativeDesktop.scrub(sample.progress)
        if sample.phase == 4 || sample.phase == 8 {
            let fast = sample.velocity * direction > 0.5
            nativeDesktop.endGesture(commit: sample.phase != 8 && (nativeDesktop.machine.progress >= 0.5 || fast))
        }
    }

    package func isOnHomeSpace(_ screen: Screen) -> Bool {
        if config.virtualWorkspaces { return !Spaces.isMaximised(display: screen.uuid) }
        guard let home = desktops.homeSpace[screen.uuid] else { return true }
        return backend.currentSpace(display: screen.uuid) == home
    }

    package func maximisedSpaces() -> [CGWindowID: UInt64] {
        var found: [CGWindowID: UInt64] = [:]
        let stillMaximised = Set(scanner.results.values.flatMap(\.maximised))
        leavingMaximised = leavingMaximised.filter {
            stillMaximised.contains($0.key) && Date().timeIntervalSince($0.value) < 3
        }
        for scan in scanner.results.values {
            for id in scan.maximised
            where windows[id] != nil && !scan.minimized.contains(id) && leavingMaximised[id] == nil {
                if let spaces = scanner.desktop.spaces[id], spaces.count == 1, let space = spaces.first {
                    found[id] = space
                }
            }
        }
        return found
    }

    package func makeCurrentSpaceHome() {
        guard config.virtualWorkspaces else { return }
        updateNativeCatalog(backend.screens())
        refresh()
        surface.showHUD("CatWM controls this Desktop", on: currentScreen()?.nsScreen)
    }
}
