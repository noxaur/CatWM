import AppKit
import QuartzCore

extension WindowManager {
    @discardableResult
    package func goToSpace(_ number: Int, autoCorrect: Bool = true) -> Int? {
        if let combo = backend.desktopShortcut(number) {
            postKey(combo)
            desktops.pendingSpace = nil
            return 1
        }
        let screens = backend.screens()
        let point = mouseLocation()
        guard let screen = screens.first(where: { $0.frame.contains(point) }) ?? currentScreen(),
              let info = backend.spaceList(display: screen.uuid), var cur = info.current else {
            Log.info("spaces: can't read the space list")
            return nil
        }
        guard number >= 1, number <= info.desktops.count else {
            surface.showHUD("There is no space \(number)", on: screen.nsScreen)
            return nil
        }
        if let pending = desktops.pendingSpace, pending.display == screen.uuid, Date() < pending.until {
            cur = pending.index
        }
        let delta = info.desktops[number - 1] - cur
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
        desktops.pendingSpace = .init(display: screen.uuid, index: info.desktops[number - 1],
                                      until: Date().addingTimeInterval(settle))
        desktops.spaceGeneration += 1
        let generation = desktops.spaceGeneration
        guard autoCorrect else { return abs(delta) }
        DispatchQueue.main.asyncAfter( // style-ok: no event marks the last queued Desktop step
            deadline: .now() + settle
        ) { [weak self] in
            self?.correctSpace(display: screen.uuid, target: info.desktops[number - 1], generation: generation,
                               attemptsLeft: 2)
        }
        return abs(delta)
    }

    package func switchSpace(_ number: Int) { goToSpace(number) }

    package func correctSpace(display: String, target: Int, generation: Int, attemptsLeft: Int) {
        guard generation == desktops.spaceGeneration, attemptsLeft > 0,
              let info = backend.spaceList(display: display), let cur = info.current, cur != target,
              let combo = backend.stepShortcut(right: target > cur) else { return }
        let delta = target - cur
        Log.info("spaces: landed on \(cur + 1) instead of \(target + 1); correcting by \(delta)")
        for _ in 0..<abs(delta) { postKey(combo) }
        let settle = 0.6 + 0.15 * Double(abs(delta))
        desktops.pendingSpace = .init(display: display, index: target, until: Date().addingTimeInterval(settle))
        DispatchQueue.main.asyncAfter( // style-ok: no event marks the last queued Desktop step
            deadline: .now() + settle
        ) { [weak self] in
            self?.correctSpace(display: display, target: target, generation: generation, attemptsLeft: attemptsLeft - 1)
        }
    }

    package func stepToSpace(_ space: UInt64, then arrived: @escaping @MainActor () -> Void) -> Bool {
        for screen in backend.screens() {
            guard let info = backend.spaceList(display: screen.uuid), let target = info.ids.firstIndex(of: space),
                  let cur = info.current, cur != target, let combo = backend.stepShortcut(right: target > cur)
            else { continue }
            let steps = abs(target - cur)
            desktops.spaceArrival = .init(display: screen.uuid, space: space,
                                          until: Date().addingTimeInterval(1 + 0.5 * Double(steps)), arrived: arrived)
            for _ in 0..<steps { postKey(combo) }
            return true
        }
        return false
    }

    package func activeSpaceChanged(at now: Date = Date()) {
        guard let arrival = desktops.spaceArrival,
              now > arrival.until || backend.currentSpace(display: arrival.display) == arrival.space else { return }
        desktops.spaceArrival = nil
        if now <= arrival.until { arrival.arrived() }
    }

    package func moveToSpace(_ number: Int) {
        guard !desktops.movingToSpace, let window = focusedWindow() else { return }
        let frame = window.frameUnlessStalled
        guard !frame.isNull else { return }
        let points = grabPoints(for: window, frame: frame)
        guard !points.isEmpty else {
            surface.showHUD("This window has nothing to grab", on: screen(of: window)?.nsScreen)
            Log.info("move to space: no grab point for \(window.bundleID ?? "pid \(window.pid)")")
            return
        }
        desktops.movingToSpace = true
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
        if sample.phase == 1 { desktops.nativeGestureSign = nil }
        if desktops.nativeGestureSign == nil, abs(sample.progress) > 0.001, !nativeDesktop.isRunning {
            guard let screen = backend.screens().first(where: { $0.frame.contains(mouseLocation()) }) else { return }
            updateNativeCatalog(backend.screens())
            let space = backend.currentSpace(display: screen.uuid)
            guard let source = desktops.nativeCatalog.entry(space: space) else { return }
            let direction = sample.progress > 0 ? 1 : -1
            guard let name = desktops.nativeCatalog.step(from: source.name, by: direction),
                  let target = desktops.nativeCatalog.entry(name) else { return }
            desktops.nativeGestureSign = Double(direction)
            configureNativeController(focusing: nil, focus: true, quiet: false)
            nativeDesktop.beginGesture(.init(workspace: name, display: target.display, space: target.space))
        }
        guard let sign = desktops.nativeGestureSign else { return }
        let progress = min(1, max(0, sample.progress * sign))
        nativeDesktop.scrub(progress)
        if sample.phase == 4 || sample.phase == 8 {
            nativeDesktop.endGesture(commit: sample.phase != 8 && (progress >= 0.5 || sample.velocity * sign > 0.5))
            desktops.nativeGestureSign = nil
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
