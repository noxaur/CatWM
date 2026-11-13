import AppKit

extension WindowManager {
    package func isShown(_ workspace: String?) -> Bool { model.isShown(workspace) }

    package var currentWorkspace: String? {
        guard let screen = currentScreen() else { return nil }
        if let request = nativeDesktop.requested, request.display == screen.uuid, isVirtual(request.workspace) {
            return request.workspace
        }
        return virtualShown[screen.uuid]
    }

    package func resolveWorkspace(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        let cur = currentWorkspace ?? "1"
        if trimmed.isEmpty { return nil }
        if lower == "previous" { return currentScreen().flatMap { previousWorkspace[$0.uuid] } }
        if lower.hasPrefix("name:") { return String(trimmed.dropFirst(5)) }
        for prefix in ["r", "m", ""] where lower.hasPrefix(prefix + "+") || lower.hasPrefix(prefix + "-") {
            guard let delta = Int(lower.dropFirst(prefix.count).replacingOccurrences(of: "+", with: "")) else { break }
            if let name = desktops.nativeCatalog.step(from: cur, by: delta) { return name }
            let occupied = workspaceOf.contains { $0.value == cur && windows[$0.key] != nil }
            let display = desktops.nativeCatalog.entry(cur)?.display ?? currentScreen()?.uuid ?? ""
            return delta > 0 && occupied && config.removesEmptyWorkspaces
                ? desktops.nativeCatalog.freeNumber(on: display) : nil
        }
        if lower.hasPrefix("e+") || lower.hasPrefix("e-"),
           let delta = Int(lower.dropFirst(1).replacingOccurrences(of: "+", with: "")) {
            let occupied = Set(workspaceOf.values).union(virtualShown.values)
                .filter { isVirtual($0) && !isPending($0) }
                .sorted(by: WorkspaceKey.precedes)
            return Self.step(occupied, from: cur, by: delta, sortedBy: WorkspaceKey.precedes)
        }
        if config.workspacesPerDisplay, let number = Int(trimmed), number >= 1, let display = currentScreen()?.uuid {
            return WorkspaceKey.make(String(number), on: display, perDisplay: true)
        }
        return trimmed
    }

    package static func step(_ sorted: [String], from current: String, by delta: Int,
                             sortedBy before: (String, String) -> Bool) -> String? {
        guard !sorted.isEmpty else { return nil }
        let index = sorted.firstIndex(of: current) ?? {
            let next = sorted.firstIndex { before(current, $0) } ?? sorted.count
            return delta > 0 ? next - 1 : next
        }()
        return sorted[index.wrapped(by: delta, in: sorted.count)]
    }

    package func workspaceKey(for screen: Screen) -> String {
        shown[screen.uuid]
            ?? WorkspaceKey.space(display: screen.uuid, space: backend.currentSpace(display: screen.uuid))
    }

    package func workspaceNumber(_ workspace: String) -> String { WorkspaceKey.number(workspace) }

    package func showWorkspaceNumber(_ number: String) {
        if let workspace = resolveWorkspace(number) { showWorkspace(workspace) }
    }

    package func isVirtual(_ workspace: String?) -> Bool {
        workspace.map { !$0.hasPrefix(WorkspaceKey.spacePrefix) } ?? false
    }

    package func isPending(_ workspace: String?) -> Bool { workspace?.hasPrefix(WorkspaceKey.pendingPrefix) == true }

    @discardableResult
    package func syncWorkspaces(screens: [Screen], present: Set<CGWindowID>) -> WorkspaceReconciliation {
        let timing = TilingTiming("reconcile", windows: present.count)
        defer { timing.finish() }
        if config.virtualWorkspaces { return syncNativeWorkspaces(screens: screens, present: present) }
        let held = desktops.movingToSpace || NSEvent.pressedMouseButtons & 1 != 0
        let observation = WorkspaceObservation(
            displays: screens.map {
                .init(id: $0.uuid, frame: $0.frame, space: backend.currentSpace(display: $0.uuid),
                      spaces: Set(Spaces.recentList(display: $0.uuid)?.ids ?? []))
            },
            frames: windows.mapValues(\.cachedFrame), present: present,
            held: held ? present : nativeMoves.movingIDs.union(present.filter { animator.isBusy($0) }),
            maximised: maximisedSpaces())
        let plan = WorkspaceReconciliation.reconcile(observation, model: model, displayOf: displayOf)
        model = plan.model
        displayOf = plan.displayOf
        return plan
    }

    package func owner(_ window: Window) -> String { "\(window.pid) \(window.bundleID ?? "")" }

    package func showWorkspace(
        _ workspace: String, focusing preferred: Window? = nil, focus takesFocus: Bool = true
    ) {
        guard config.virtualWorkspaces else { return }
        showNativeWorkspace(workspace, focusing: preferred, focus: takesFocus, quiet: closeAndSort.quietWorkspaceHUD)
    }

    package func showWorkspaceHUD(_ workspace: String, on monitor: Screen) {
        let number = workspaceNumber(workspace)
        let text = labels[workspace].map { "\(number) · \($0)" } ?? number
        let layout = state(workspace: workspace).layout
        DispatchQueue.main.async { [weak self] in
            guard self?.shown[monitor.uuid] == workspace else { return }
            self?.surface.showHUD(text, layout: layout, on: monitor.nsScreen)
        }
    }

    package func focusShownWorkspace(_ workspace: String, preferred: Window?, on screen: Screen) {
        let candidates = [preferred?.id, lastFocused[workspace]].compactMap(\.self) + order
        if let id = candidates.first(where: { id in
            workspaceOf[id] == workspace && windows[id].map { window in
                !window.minimized && NSRunningApplication(processIdentifier: window.pid)?.isHidden != true
            } == true
        }), let window = windows[id] {
            focus(window, warp: !screen.frame.contains(mouseLocation()))
        } else {
            parkFocus(on: screen)
        }
    }

    package func claimForCurrentWorkspace(_ ids: [CGWindowID]) {
        guard config.virtualWorkspaces, !restoringTemplate, let here = currentWorkspace else { return }
        for id in ids where workspaceOf[id] != here {
            guard let target = desktops.nativeCatalog.entry(here),
                  Spaces.of(window: id).contains(target.space) else { continue }
            model.assign(id, to: here)
        }
    }
}
