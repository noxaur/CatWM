import AppKit

extension WindowManager {
    package func requestFocusObservation() {
        guard isStarted, let pid = frontmostPID() else { return }
        let observation = focusRequests.beginObservation(pid: pid)
        if observation.cancelledRequest { animator.cancelFocus() }
        guard observation.shouldRead else { return }
        let generation = observation.generation
        focusRequests.focusReader.observe(pid) { [weak self] result in
            guard let self else { return }
            let current = self.focusRequests.finishObservation(pid: pid, generation: generation)
            guard self.isStarted, self.frontmostPID() == pid else { return }
            guard current else { self.requestFocusObservation(); return }
            switch result {
            case .focused(let id): self.acceptFocus(pid: pid, id: id, confirmsRequest: true)
            case .unavailable:
                guard self.focusRequests.needsObservation else { return }
                self.focusRequests.retryRead { [weak self] in
                    guard let self, self.focusRequests.isCurrent(generation),
                          self.frontmostPID() == pid else { return }
                    self.requestFocusObservation()
                }
            }
        }
    }

    package func acceptFocus(pid: pid_t, id: CGWindowID?, confirmsRequest: Bool = false) {
        guard frontmostPID() == pid else { return }
        surface.batchTabChanges {
            acceptReportedFocus(pid: pid, id: id, confirmsRequest: confirmsRequest)
        }
        notifyChange()
    }

    private func acceptReportedFocus(pid: pid_t, id: CGWindowID?, confirmsRequest: Bool) {
        focusRequests.report(pid: pid, id: id, confirmsRequest: confirmsRequest)
        if let id, windows[id] == nil { scheduleRefresh(after: 0.1) }
        followFocus()
        followTabFocus(id)
        if let waiting = focusRequests.takeWaitingRefocus() {
            if waiting.pid == pid { refocusRecent(on: waiting.workspace) }
        }
        let commands = focusRequests.takeCommands()
        for command in commands where command.pid == frontmostPID() {
            dispatch(command.dispatcher, command.arg, inMode: command.inMode)
        }
        surface.focusChanged()
        surface.restackTabStrips()
    }

    package func deferFocusCommand(_ dispatcher: String, arg: String, inMode: Bool) -> Bool {
        guard isStarted, let pid = frontmostPID(), pid != getpid(),
              focusRequests.reportedFocus?.pid != pid else { return false }
        if focusRequests.pendingFocus != nil, focusedWindow() != nil { return false }
        guard Actions.requiresFocus(BindRow(mods: "", key: "", dispatcher: dispatcher, args: arg)) else { return false }
        focusRequests.enqueue(.init(pid: pid, dispatcher: dispatcher, arg: arg, inMode: inMode))
        requestFocusObservation()
        return true
    }

    package func cancelFocusRequest() {
        focusRequests.cancel()
        animator.cancelFocus()
    }
}
