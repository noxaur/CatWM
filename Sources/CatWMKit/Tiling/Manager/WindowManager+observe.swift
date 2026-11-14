import AppKit

extension WindowManager {
    package func observe(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }
        observe(pid: app.processIdentifier)
    }

    package func observe(pid: pid_t) {
        guard isStarted, pid != getpid(), observers[pid] == nil, scanner.keeps(pid) else { return }
        guard observing[pid] == nil else { return }
        let token = UUID()
        observing[pid] = token
        scanner.run(pid) { [weak self] in
            var observer: AXObserver?
            let created = AXObserverCreate(pid, axCallback, &observer) == .success
            var added = false
            if created, let observer {
                let element = axApp(pid)
                for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                             kAXApplicationHiddenNotification, kAXApplicationShownNotification]
                where AXObserverAddNotification(observer, element, name as CFString, nil) == .success {
                    added = true
                }
            }
            let registered = added ? observer : nil
            DispatchQueue.main.async {
                guard let self, self.isStarted, self.observing[pid] == token else { return }
                self.observing[pid] = nil
                guard let registered, self.backend.isRunning(pid) else { return }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(registered), .defaultMode)
                self.observers[pid] = registered
                self.windows.values.filter { $0.pid == pid }.forEach(self.watch)
            }
        }
    }

    package func watch(_ window: Window) {
        guard let observer = observers[window.pid] else { return }
        let obs = AXReference(observer)
        scanner.run(window.pid) {
            for name in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                         kAXWindowDeminiaturizedNotification, kAXWindowMovedNotification,
                         kAXWindowResizedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(obs.object, window.element, name as CFString, nil)
            }
        }
    }

    package func handle(_ notification: String, _ element: AXUIElement) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            closeAndSort.lastClose = Date()
            requestFocusObservation()
            scheduleRefresh()
            surface.focusChanged()
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard let window = windows.values.first(where: { CFEqual($0.element, element) }),
                  !animator.isBusy(window.id), !desktops.movingToSpace, window.id != tabUI.drag.lifted else { return }
            let id = window.id
            observeFrame(window)
            if primaryButtonDown() {
                if drags.isEmpty { tabUI.drag.beginNative(id) }
                drags[id] = (drags[id] ?? false) || notification == kAXWindowResizedNotification
            } else if !window.isFloating {
                if notification == kAXWindowResizedNotification {
                    adoptNativeZoom(window)
                } else {
                    scheduleRefresh(after: 0.25)
                }
            }
        case kAXFocusedWindowChangedNotification:
            observeFocus(element)
            surface.focusChanged()
            notifyChange()
        case kAXTitleChangedNotification:
            titleChanged(element)
        case kAXWindowMiniaturizedNotification:
            windowMinimizeChanged(element, minimized: true)
        case kAXWindowDeminiaturizedNotification:
            windowMinimizeChanged(element, minimized: false)
        case kAXWindowCreatedNotification:
            scheduleRefresh(after: 0)
            for delay in [0.3, 1.0] {
                DispatchQueue.main.asyncAfter( // style-ok: a new window becomes readable with no event
                    deadline: .now() + delay
                ) { [weak self] in
                    self?.scheduleRefresh(after: 0)
                }
            }
        default:
            scheduleRefresh()
        }
    }

    package func readFrames(_ windows: [Window], completion: @escaping () -> Void) {
        let group = DispatchGroup()
        for window in windows {
            let revision = window.frameRevision
            group.enter()
            scanner.run(window.pid) { [weak self] in
                let readAt = Date()
                let frame = window.backend.frame(of: window)
                DispatchQueue.main.async {
                    if let self, self.windows[window.id] === window, !self.animator.isBusy(window.id) {
                        window.remember(frame, ifRevision: revision, readAt: readAt)
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main, execute: completion)
    }

    package func observeFrame(_ window: Window) {
        guard frameReads[window.id] == nil else { dirtyFrames.insert(window.id); return }
        let token = UUID()
        frameReads[window.id] = token
        let revision = window.frameRevision
        scanner.run(window.pid) { [weak self] in
            let readAt = Date()
            let frame = window.backend.frame(of: window)
            DispatchQueue.main.async {
                guard let self, self.frameReads[window.id] == token else { return }
                self.frameReads[window.id] = nil
                guard self.windows[window.id] === window else { return }
                if !self.animator.isBusy(window.id) { window.remember(frame, ifRevision: revision, readAt: readAt) }
                if self.drags[window.id] == false { self.dragTabGroup(window) }
                if self.dirtyFrames.remove(window.id) != nil { self.observeFrame(window) }
            }
        }
    }

    package func observeFocus(_ element: AXUIElement) {
        focusRequests.invalidateObservation()
        if let window = windows.values.first(where: { CFEqual($0.element, element) }),
           frontmostPID() == window.pid {
            acceptFocus(pid: window.pid, id: window.id)
        } else {
            requestFocusObservation()
        }
    }

    package func forget(_ id: CGWindowID, keepRecovery: Bool = false) {
        if !keepRecovery, let window = windows[id] { tilingRecovery.forget(recoveryIdentity(window)) }
        animator.forget(id)
        placementHolds.forget(id)
        let focused = focusClock > 0 && focusStamps[id] == focusClock
        showHeir(of: id, focused: focused)
        if focusRequests.forget(id, refocusOn: !restoringTemplate && focused ? workspaceOf[id] : nil) {
            animator.cancelFocus()
        }
        windows[id] = nil
        surface.windowForgotten(id)
        frameReads[id] = nil
        dirtyFrames.remove(id)
        snapNextPlacement.remove(id)
        model.forget(id)
        floats.floatFrames[id] = nil; floats.floatFullscreen[id] = nil; targets[id] = nil; minSizes[id] = nil
        corrections[id] = nil; drags[id] = nil
        displayOf[id] = nil
        nativeMoves.forget(id)
        closeAndSort.closingNow.remove(id)
        visible.remove(id)
    }
}

package func axCallback(_: AXObserver, _ element: AXUIElement, _ notification: CFString,
                        _: UnsafeMutableRawPointer?) {
    let name = notification as String
    let reference = AXReference(element)
    onMainThread { WindowManager.shared.handle(name, reference.object) }
}

extension WindowManager {
    package func windowMinimizeChanged(_ element: AXUIElement, minimized: Bool) {
        guard let window = windows.values.first(where: { CFEqual($0.element, element) }),
              window.minimized != minimized else {
            return scheduleRefresh(after: 0)
        }
        window.minimized = minimized
        window.observedAt = Date()
        guard !minimized else { return scheduleRefresh(after: 0) }
        claimForCurrentWorkspace([window.id])
        restoreTabGroup(of: window.id)
        restoredEarly[window.id] = Date()
        snapNextPlacement.insert(window.id)
        refresh(instant: true, placing: [window.id])
        scheduleRefresh(after: 0)
    }

    package func prewarm() {
        guard !isStarted else { return }
        scanner.observeDesktop(known: []) {}
    }
}
