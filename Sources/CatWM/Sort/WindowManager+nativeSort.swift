import AppKit
import CatWMKit

extension WindowManager {
    @discardableResult
    func finishSort(closing ids: [CGWindowID], goTo: String?, focus: Bool, opening maximised: CGWindowID? = nil,
                    leavingMaximised moves: [CGWindowID: String] = [:]) -> Task<Void, Never> {
        Task { @MainActor in
            await self.commitNativeSort()
            for (id, workspace) in moves { await self.leaveMaximised(id, to: workspace) }
            self.finishSortAfterNative(closing: ids, goTo: goTo, focus: focus, opening: maximised)
        }
    }

    @MainActor private func commitNativeSort() async {
        for name in desktops.nativeSortNames.sorted(by: WorkspaceKey.precedes) {
            guard let display = monitorOf[name],
                  let screen = backend.screens().first(where: { $0.uuid == display }) else {
                continue
            }
            do { _ = try await ensureNativeWorkspace(name, on: screen) } catch {
                surface.showHUD(error.localizedDescription, on: screen.nsScreen)
            }
        }
        let assignments = workspaceOf
        for (id, name) in assignments {
            guard let target = desktops.nativeCatalog.entry(name), let window = windows[id], !window.maximised,
                  Spaces.of(window: id) != [target.space] else { continue }
            nativeMoves.begin(id)
            animator.cancel(id)
            let moved = await withCheckedContinuation { continuation in
                Spaces.move(window: id, to: target.space) { continuation.resume(returning: $0) }
            }
            nativeMoves.finish(id)
            if moved { nativeMoves.finish(id, on: target.space) } else {
                surface.showHUD("macOS couldn't move a window to workspace \(name)", on: currentScreen()?.nsScreen)
            }
        }
        desktops.nativeSortNames = []
    }

    @MainActor func leaveMaximised(_ id: CGWindowID, to workspace: String) async {
        guard let window = windows[id], let screen = backend.screens().first(where: {
            $0.uuid == monitorOf[workspace]
        }), window.unlessStalled(false, { window.element.set("AXFullScreen", kCFBooleanFalse) }) else {
            Log.info("sort: \(id) refused to leave full screen")
            return
        }
        nativeMoves.begin(id)
        defer { nativeMoves.finish(id); scheduleRefresh(after: 0) }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        func leaving() -> Bool { window.maximisedUnlessStalled || !DesktopUI.isSettled(screen) }
        guard await poll(5, every: 50_000_000, until: { !leaving() || !window.isValidUnlessStalled }), !leaving() else {
            surface.showHUD("macOS did not finish leaving full screen", on: screen.nsScreen)
            return
        }
        do {
            let target = try await ensureNativeWorkspace(workspace, on: screen)
            var moved = false
            repeat {
                moved = await withCheckedContinuation { continuation in
                    Spaces.move(window: id, to: target.space) { continuation.resume(returning: $0) }
                }
                if !moved { try await Task.sleep(nanoseconds: 100_000_000) }
            } while !moved && window.isValidUnlessStalled && ProcessInfo.processInfo.systemUptime < deadline
            guard moved else { throw DesktopTransitionError.check("macOS couldn't move this window") }
            nativeMoves.finish(id, on: target.space)
            model.assign(id, to: workspace)
            model.maximisedHost = model.maximisedHost.filter { $0.value != id }
            leavingMaximised[id] = Date()
        } catch {
            Log.info("sort: leave full screen failed: \(error.localizedDescription)")
            surface.showHUD(error.localizedDescription, on: screen.nsScreen)
        }
    }
}
