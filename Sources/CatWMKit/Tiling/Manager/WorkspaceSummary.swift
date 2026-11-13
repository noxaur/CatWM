import AppKit

package struct WorkspaceSummary {
    package struct Entry {
        package let name: String
        package let windows: Int
        package let shown: Bool
    }

    package let current: String?
    package let all: [Entry]
}

package struct MenuBarState {
    package let workspace: String?
    package let layout: Layout
    package let pids: [pid_t]
}

extension WindowManager {
    package func workspaceSummary() -> WorkspaceSummary {
        guard config.virtualWorkspaces, isStarted else { return WorkspaceSummary(current: nil, all: []) }
        var counts: [String: Int] = [:]
        for (id, workspace) in workspaceOf where windows[id] != nil && isVirtual(workspace) && !isPending(workspace) {
            counts[workspace, default: 0] += 1
        }
        var names = Set(counts.keys).union(desktops.nativeCatalog.entries.map(\.name))
            .union(virtualShown.values).sorted(by: WorkspaceKey.precedes)
        if config.workspacesPerDisplay, let display = currentScreen()?.uuid {
            names = desktops.nativeCatalog.entries(on: display).map(\.name)
        }
        let showing = Set(virtualShown.values)
        return WorkspaceSummary(
            current: currentWorkspace.map(workspaceNumber),
            all: names.map {
                WorkspaceSummary.Entry(name: workspaceNumber($0), windows: counts[$0] ?? 0, shown: showing.contains($0))
            }
        )
    }

    package func menuBarState() -> MenuBarState? {
        guard isStarted, let screen = currentScreen() else { return nil }
        let shownWorkspace = shown[screen.uuid]
        let workspace: String?
        if config.virtualWorkspaces {
            workspace = virtualShown[screen.uuid].map(workspaceNumber)
        } else if let list = Spaces.list(display: screen.uuid), let cur = list.current,
                  let index = list.desktops.firstIndex(of: cur) {
            workspace = String(index + 1)
        } else {
            workspace = nil
        }
        let here = order.filter { workspaceOf[$0] == shownWorkspace && present.contains($0) }.compactMap { windows[$0] }
        var seen = Set<pid_t>()
        let pids = (here.filter { !$0.isFloating } + here.filter(\.isFloating)).map(\.pid)
            .filter { seen.insert($0).inserted }
        return MenuBarState(workspace: workspace, layout: state(for: screen).layout, pids: pids)
    }
}
