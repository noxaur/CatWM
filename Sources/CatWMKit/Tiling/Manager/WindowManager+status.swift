import AppKit

extension WindowManager {
    package func status() -> Status {
        let screens = backend.screens()
        let managed = visible.compactMap { windows[$0] }
        return Status(trusted: Permission.accessibility.isGranted, keybindsActive: surface.keybindsActive,
                      running: isStarted,
                      tilingEnabled: tilingEnabled,
                      launchAtLogin: surface.loginItem.enabled, loginNeedsApproval: surface.loginItem.needsApproval,
                      inputMonitoring: Permission.inputMonitoring.isGranted,
                      tiled: managed.filter { !$0.isFloating }.count, floating: managed.filter(\.isFloating).count,
                      screens: isStarted ? screens.map { screen in
                          ScreenStatus(uuid: screen.uuid, name: screen.name,
                                       layout: state(for: screen).layout,
                                       workspace: isVirtual(shown[screen.uuid]) ? (shown[screen.uuid] ?? "") : "")
                      } : [])
    }

    package func dumpLines() -> [String] {
        var lines = [
            "state: trusted=\(Permission.accessibility.isGranted) keybinds=\(surface.keybindsActive) "
                + "tiling=\(tilingEnabled) focused=\(focusedWindow()?.id ?? 0)"
        ]
        for screen in backend.screens() {
            let screenState = state(for: screen)
            lines.append(
                "  screen \(screen.name) workspace=\(shown[screen.uuid] ?? "?") "
                    + "home=\(isOnHomeSpace(screen)) layout=\(screenState.layout.rawValue) "
                    + "ratio=\(screenState.ratio) main=\(screenState.mainCount) usable=\(usableRect(screen))"
            )
            for id in tiled(on: screen) {
                guard let window = windows[id] else { continue }
                let matches = targets[id].map { window.frame.approxEqual($0, tolerance: 2) } ?? false
                lines.append(
                    "    tiled \(id) \(window.bundleID ?? "pid \(window.pid)") target=\(targets[id] ?? .null) "
                        + "actual=\(window.frame) \(matches ? "OK" : "MISMATCH")"
                )
            }
        }
        for group in tabs.groups {
            let members = group.members.map { $0 == group.active ? "[\($0)]" : "\($0)" }
            lines.append("  tabs \(members.joined(separator: " "))")
        }
        for id in visible {
            guard let window = windows[id], window.isFloating else { continue }
            lines.append("  floating \(id) \(window.bundleID ?? "") \(window.frame)")
        }
        let parked = workspaceOf.sorted(by: { $0.value < $1.value })
        for (id, workspace) in parked where present.contains(id) && !visible.contains(id) {
            lines.append(
                "  parked \(id) \(windows[id]?.bundleID ?? "") workspace=\(workspace) "
                    + "frame=\(windows[id]?.frame ?? .null)"
            )
        }
        return lines
    }

    package struct ScreenStatus: Equatable {
        package var uuid: String
        package var name: String
        package var layout: Layout
        package var workspace: String
    }

    package struct Status: Equatable {
        package var trusted: Bool
        package var keybindsActive: Bool
        package var running: Bool
        package var tilingEnabled: Bool
        package var launchAtLogin: Bool
        package var loginNeedsApproval: Bool
        package var inputMonitoring: Bool
        package var tiled: Int
        package var floating: Int
        package var screens: [ScreenStatus]
    }
}
