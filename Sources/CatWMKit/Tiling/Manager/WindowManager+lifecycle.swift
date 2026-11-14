import AppKit

extension WindowManager {
    package func start() {
        startServices()
        guard config.features.contains(.tiling) else { return Log.info("start: tiling is off in the config") }
        startTiling()
    }

    package func startServices() {
        guard !servicesStarted else { return }
        servicesStarted = true
        if config.features.contains(.socket) { ControlServer.shared.start(path: socketPath) }
        store.watch { [weak self] in self?.apply($0, showHUD: true) }
    }

    package func stopServices() {
        servicesStarted = false
        ControlServer.shared.stop()
        store.stopWatching()
    }

    package func startTiling() {
        guard !isStarted else { return }
        startEngine()
        loadWorkspaces()
        if config.features.contains(.tabGroups) { loadTabs() }
        if config.virtualWorkspaces { DesktopUI.prepare() }
        Log.verbose = config.debugLogging || Log.verboseLaunch
        Log.info(
            "start: trusted=\(Permission.accessibility.isGranted) "
                + "windowServerFocus=\(WindowServerFocus.isAvailable) screens=\(backend.screens().count)"
        )
        config.errors.forEach { Log.info("config: \($0)") }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

        observeApplicationNotifications()
        observeSpaceAndScreenNotifications()
        installEventMonitors()
        installInputHandlers()
        watchClaims()

        if !embedded { prepareFocusSink() }
        requestFocusObservation()
        refresh()
        for delay in [0.5, 1.5, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter( // style-ok: apps at login become readable with no event
                deadline: .now() + delay
            ) { [weak self] in self?.retryStartupScan() }
        }
    }

    package func retryStartupScan() {
        guard scanner.lastScan == 0 || scanner.applications.contains(where: \.regular) else { return }
        scheduleRefresh()
    }

    package func startEngine() {
        isStarted = true
        startedAt = Date()
        animator.onMinimumSize = { [weak self] id, size in self?.learnMinimum(id, size) }
        animator.onTopRefused = { [weak self] target, actual in self?.learnMenuBar(target, actual) }
        animator.onLanded = { [weak self] in self?.cursorRefresh.soon() }
    }

    package func watchClaims() {
        scanner.watchClaims { [weak self] pids in DispatchQueue.main.async { self?.claimsChanged(pids) } }
    }

    package func claimsChanged(_ pids: Set<pid_t>) {
        let held = Set(windows.values.map(\.pid)).union(observers.keys).union(observing.keys)
        let matters = pids.contains { held.contains($0) || NSRunningApplication(processIdentifier: $0) != nil }
        if matters { scheduleRefresh() }
    }

    package func stopTiling(then done: @escaping () -> Void = {}) {
        guard isStarted else { return done() }
        surface.stop()
        nativeGestures.stop()
        dockWindowPull.stop()
        dockArea.stop()
        nativeDesktop.stop()
        for observer in notificationObservers { observer.center.removeObserver(observer.token) }
        notificationObservers = []
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers = [:]
        observing = [:]
        scanner.stopWatchingClaims()
        refreshWork?.cancel()
        refreshWork = nil
        crowdWork.cancel()
        isStarted = false
        restoreHiddenWindows { [weak self] in
            self?.windows.keys.forEach { self?.animator.cancel($0) }
            done()
        }
        Log.info("stop: tiling stopped")
    }

    private func observe(_ name: Notification.Name, in center: NotificationCenter,
                         _ handler: @escaping @MainActor () -> Void) {
        notificationObservers.append((center, center.observeOnMain(name, handler)))
    }

    private func observeApplication(_ name: Notification.Name, in center: NotificationCenter,
                                    _ handler: @escaping @MainActor (NSRunningApplication?) -> Void) {
        let payload: @Sendable (Notification) -> NSRunningApplication? = {
            $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        }
        notificationObservers.append((center, center.observeOnMain(name, payload: payload, handler: handler)))
    }

    private func observeApplicationNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        observeApplication(NSWorkspace.didLaunchApplicationNotification, in: center) { [weak self] app in
            guard let app else { return }
            self?.applicationLaunched(app)
        }
        observeApplication(NSWorkspace.didTerminateApplicationNotification, in: center) { [weak self] app in
            guard let self, let app else { return }
            applicationTerminated(app.processIdentifier)
        }
        observe(NSWorkspace.willPowerOffNotification, in: center) { [weak self] in
            Log.info("recovery: macOS is logging out or shutting down; keeping the state of quitting apps")
            self?.poweringOffAt = Date()
        }
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            observeApplication(name, in: center) { [weak self] app in
                guard let self, app.map({ scanner.keeps($0.processIdentifier) }) ?? true else { return }
                scheduleRefresh()
            }
        }
        observeApplication(NSWorkspace.didActivateApplicationNotification, in: center) { [weak self] app in
            if let self, let echo = focusRequests.focusEcho, echo.matches(app?.processIdentifier),
               let window = windows[echo.id] {
                focus(window, warp: false)
                return
            }
            if self?.focusRequests.pendingFocus == nil { self?.animator.cancelFocus() }
            self?.requestFocusObservation()
        }
    }

    package func applicationLaunched(_ app: NSRunningApplication) {
        guard scanner.keeps(app.processIdentifier) else { return }
        observe(app)
        scheduleRefresh(after: 0)
        for delay in [0.3, 1.0, 2.5] {
            DispatchQueue.main.asyncAfter( // style-ok: a new app becomes readable with no event
                deadline: .now() + delay
            ) { [weak self] in
                self?.observe(app)
                self?.scheduleRefresh()
            }
        }
    }

    package func applicationTerminated(_ pid: pid_t) {
        release(pid)
        if scanner.keeps(pid) { scheduleRefresh() }
    }

    package func releaseClaimedApps() {
        let held = Set(windows.values.map(\.pid)).union(observers.keys).union(observing.keys)
        for pid in held.intersection(scanner.claimed) {
            Log.debug("pid \(pid) is in the scope of another instance; leaving its windows")
            release(pid)
        }
    }

    private func release(_ pid: pid_t) {
        if let obs = observers[pid] {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observers[pid] = nil
        scanner.terminated(pid)
        observing.removeValue(forKey: pid)
        windows.values.filter { $0.pid == pid }.forEach { self.forget($0.id, keepRecovery: true) }
        animator.terminated(pid)
        focusRequests.focusReader.terminated(pid)
    }

    private func observeSpaceAndScreenNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.activeSpaceDidChangeNotification, in: center) { [weak self] in
            guard let self else { return }
            activeSpaceChanged()
            scheduleRefresh(after: 0.15)
            if !config.virtualWorkspaces, config.enablesLayoutHUDOnSpaceChange, config.enablesLayoutHUD,
               let screen = currentScreen() {
                surface.showHUD(state(for: screen).layout.title, layout: state(for: screen).layout, on: screen.nsScreen)
            }
        }
        observe(NSApplication.didChangeScreenParametersNotification, in: .default) { [weak self] in
            self?.scheduleRefresh(after: 0.4)
        }
        observeLock()
    }

    private func observeLock() {
        let leave: @MainActor () -> Void = { [weak self] in self?.surface.leaveMode() }
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(name, in: NSWorkspace.shared.notificationCenter, leave)
        }
        observe(Notification.Name("com.apple.screenIsLocked"), in: DistributedNotificationCenter.default(), leave)
    }

    private func installEventMonitors() {
        let monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.mouseUp() },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
                guard let self, !self.drags.isEmpty else { return }
                self.updateTabDropHint()
            },
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.cancelFocusRequest()
                self?.surface.leaveMode()
            },
            NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                if !CursorRefresh.isOurs(event) { self?.mouseMoved() }
            }
        ]
        eventMonitors += monitors.compactMap(\.self)
    }

    private func installInputHandlers() {
        surface.apply(config)
        surface.start(self)
        nativeGestures.enabled = { [weak self] in
            guard let self else { return false }
            return self.config.virtualWorkspaces && !self.surface.keysPaused && !self.closeAndSort.sortSession
                && !self.desktops.nativeCreationBusy
        }
        nativeGestures.receive = { [weak self] in self?.handleNativeSwipe($0) }
        nativeGestures.interrupted = { [weak self] in self?.nativeDesktop.endGesture(commit: false) }
        dockWindowPull.prepare = { [weak self] point in self?.prepareDockPull(at: point) }
        startMouseTaps(logFailure: true)
    }

    package func toggleTiling() {
        tilingEnabled.toggle()
        surface.showHUD(tilingEnabled ? "Tiling on" : "Tiling off", on: currentScreen()?.nsScreen)
        refresh()
    }

    package func startMouseTaps(logFailure: Bool = false) {
        guard input.mouseTaps else { return }
        if config.features.contains(.gestures) { nativeGestures.start() }
        guard config.features.contains(.mouse), !dockWindowPull.isInstalled else { return }
        if dockWindowPull.start() {
            dockArea.start()
        } else if logFailure {
            Log.info("Dock window import: mouse event tap unavailable")
        }
    }

    package func setInputTaps(enabled: Bool) {
        surface.setKeyTap(enabled: enabled)
        dockWindowPull.setEnabled(enabled)
        nativeGestures.setEnabled(enabled)
        Log.info("input taps \(enabled ? "on" : "off")")
    }
}
