import AppKit

extension WindowManager {
    package func reload(showHUD: Bool = true) {
        apply(store.reload(), showHUD: showHUD)
    }

    package func applyStoredConfig() {
        apply(store.reload(), showHUD: false)
    }

    package func apply(_ next: Config, showHUD: Bool) {
        let old = config
        config = Self.effective(next, scope: scope)
        let changes = config.changes(from: old)
        guard !changes.isEmpty || config.diagnostics != old.diagnostics else { return }
        if changes.contains("features") { applyFeatures(from: old.features) }
        applyWorkspaceChanges(changes, wasVirtual: old.virtualWorkspaces)
        Log.verbose = config.debugLogging || Log.verboseLaunch
        if !changes.isDisjoint(with: Self.surfaceFields) { surface.apply(config) }
        if !changes.isDisjoint(with: Self.floatFields.union(["windowRules"])) { applyFloatingChanges(from: old) }
        if isStarted, !changes.subtracting(Self.liveFields).isEmpty {
            corrections = [:]
            scheduleRefresh(after: 0)
            refresh()
        }
        if !changes.isEmpty { Log.info("config: applied \(changes.sorted().joined(separator: ", "))") }
        config.errors.forEach { Log.info("config: \($0)") }
        EventBus.shared.emit("config.reloaded", ["errors": .array(config.diagnostics.map(\.json))])
        guard showHUD else { return }
        surface.showHUD(
            config.errors.isEmpty ? "Config reloaded" : "Config: \(config.errors.count) error(s), see Console",
            on: currentScreen()?.nsScreen
        )
    }

    private func applyFeatures(from old: Set<Feature>) {
        let features = config.features
        let changed = features.symmetricDifference(old)
        if servicesStarted, changed.contains(.socket) {
            if features.contains(.socket) {
                ControlServer.shared.start(path: socketPath)
            } else {
                ControlServer.shared.stop()
            }
        }
        if servicesStarted, changed.contains(.tiling) {
            if !features.contains(.tiling) { stopTiling() } else if mayTile() { startTiling() }
            return
        }
        guard isStarted else { return }
        applyInputFeatures(changed)
        if changed.contains(.tabStrips) { surface.tabsDidChange(instant: true) }
        if changed.contains(.tabGroups), !features.contains(.tabGroups) { dissolveTabs() }
    }

    private func applyInputFeatures(_ changed: Set<Feature>) {
        let features = config.features
        if changed.contains(.keys) { surface.setKeyBinds(enabled: features.contains(.keys)) }
        if !features.contains(.mouse) {
            dockWindowPull.stop()
            dockArea.stop()
        }
        if !features.contains(.gestures) { nativeGestures.stop() }
        startMouseTaps()
    }

    private func applyWorkspaceChanges(_ changes: Set<String>, wasVirtual: Bool) {
        if changes.contains("virtual-workspaces") {
            nativeDesktop.stop()
            tilingRecovery = TilingRecovery()
            if wasVirtual { restoreHiddenWindows() }
            model.resetWorkspaces()
            labels = [:]; closeAndSort.sortSnapshot = nil; closeAndSort.closingNow = []; closeAndSort.closingApps = []
            surface.abandonOverview()
            Log.info("workspaces: \(config.virtualWorkspaces ? "CatWM workspaces" : "macOS Spaces")")
        } else if changes.contains("workspaces-per-display") {
            nativeDesktop.stop()
            renumberWorkspaces()
        }
    }

    package static let surfaceFields: Set<String> = [
        "bindings", "mod", "virtual-workspaces", "mode-effect", "keyboard-finish", "tab-notification-badges",
        "dim-other-windows", "dim-strength", "blur-other-windows", "blur-radius", "resize-animation",
        "keyboard-help-key"
    ]

    package static let floatFields: Set<String> = ["floating", "floating-is-blacklist", "float-small-windows"]

    package static let liveFields: Set<String> = surfaceFields.subtracting(["virtual-workspaces"]).union([
        "features", "mouse-follows-focus", "focus-follows-mouse", "focus-follows-mouse-in-mode-only",
        "mouse-swaps-windows", "mouse-resizes-windows", "enables-layout-hud", "enables-layout-hud-on-space-change",
        "keyboard-help", "cursor-actions", "template-app-scripting", "switcher-instant-jump",
        "switcher-jump-delay", "switcher-exclude", "animate", "animation-duration", "animation-curve",
        "animation-bounce", "panel-animation", "debug-logging", "perf-reports", "sort-nudge", "window-resize-step",
        "stay-on-workspace-after-close", "remove-empty-workspaces"
    ])
}
