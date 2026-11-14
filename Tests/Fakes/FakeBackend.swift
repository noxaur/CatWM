import AppKit
import CatWMKit
import os

package final class FakeBackend: WindowBackend, Sendable {
    package let clock = FakeClock()

    package init() { RealInput.block() }

    package struct FakeWindow {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        var frame: CGRect
        var title: String?
        var minSize: CGSize
        var resizable: Bool
        var minimized = false
    }

    package enum Write: Equatable {
        case position(CGWindowID, CGPoint)
        case size(CGWindowID, CGSize)

        package var id: CGWindowID {
            switch self {
            case let .position(id, _), let .size(id, _): id
            }
        }
    }

    package enum Input: Equatable {
        case key(UInt16, flags: UInt64)
        case mouse(UInt32, CGPoint)
        case warp(CGPoint)
    }

    struct Held {
        var id: CGWindowID
        var start: CGPoint
        var current: CGPoint
    }

    struct State {
        var screenList: [Screen] = []
        var apps: [pid_t: String?] = [:]
        var windowList: [CGWindowID: FakeWindow] = [:]
        var stacking: [CGWindowID] = []
        var focusedIn: [pid_t: CGWindowID] = [:]
        var front: pid_t?
        var writeLog: [Write] = []
        var cursorRefreshCount = 0
        var placementCheckCount = 0
        var clockedAnimators: Set<ObjectIdentifier> = []
        var onCursorRefresh: (() -> Void)?
        var nextID: CGWindowID = 1
        var nextDisplay: CGDirectDisplayID = 1
        var scanGate: DispatchSemaphore?
        var inputLog: [Input] = []
        var pointer = CGPoint.zero
        var desktopCount = 3
        var desktop = 1
        var desktopOf: [CGWindowID: Int] = [:]
        var desktopSwitches: [Int] = []
        var held: Held?
    }

    let state = OSAllocatedUnfairLock(uncheckedState: State())

    @discardableResult
    package func addScreen(frame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900),
                           visible: CGRect? = nil) -> Screen {
        state.withLockUnchecked { state in
            let screen = Screen(id: state.nextDisplay, uuid: "fake-display-\(state.nextDisplay)", frame: frame,
                                visible: visible ?? frame, isBuiltin: false, nsScreen: nil)
            state.nextDisplay += 1
            state.screenList.append(screen)
            return screen
        }
    }

    package func removeScreen(_ screen: Screen) {
        state.withLockUnchecked { state in state.screenList.removeAll { $0.uuid == screen.uuid } }
    }

    @discardableResult
    package func addWindow(pid: pid_t = -100, bundleID: String? = "test.fake.app",
                           frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600),
                           title: String? = "Window", minSize: CGSize = .zero, resizable: Bool = true) -> CGWindowID {
        precondition(pid < 0, "A fake app uses a negative pid, so no AX call reaches a real app")
        return state.withLockUnchecked { state in
            let id = state.nextID
            state.nextID += 1
            state.apps[pid] = state.apps[pid] ?? bundleID
            state.windowList[id] = FakeWindow(id: id, pid: pid, element: AXUIElementCreateApplication(-Int32(id)),
                                        frame: frame, title: title, minSize: minSize, resizable: resizable)
            state.stacking.insert(id, at: 0)
            state.focusedIn[pid] = id
            state.front = pid
            return id
        }
    }

    package func close(_ id: CGWindowID) {
        state.withLockUnchecked { state in
            guard let closed = state.windowList.removeValue(forKey: id) else { return }
            state.stacking.removeAll { $0 == id }
            if state.focusedIn[closed.pid] == id {
                state.focusedIn[closed.pid] = state.stacking.first { state.windowList[$0]?.pid == closed.pid }
            }
        }
    }

    package func close(_ window: Window) -> String {
        close(window.id)
        return "pressed"
    }

    package func quit(_ pid: pid_t) {
        state.withLockUnchecked { state in
            let gone = state.windowList.values.filter { $0.pid == pid }.map(\.id)
            gone.forEach { state.windowList[$0] = nil }
            state.stacking.removeAll { gone.contains($0) }
            state.apps[pid] = nil
            state.focusedIn[pid] = nil
            if state.front == pid { state.front = state.stacking.first.flatMap { state.windowList[$0]?.pid } }
        }
    }

    package func minimize(_ id: CGWindowID, _ minimized: Bool = true) {
        state.withLockUnchecked { state in state.windowList[id]?.minimized = minimized }
    }

    package func userFocuses(_ id: CGWindowID) {
        state.withLockUnchecked { state in
            guard let window = state.windowList[id] else { return }
            state.front = window.pid
            state.focusedIn[window.pid] = id
            state.stacking.removeAll { $0 == id }
            state.stacking.insert(id, at: 0)
        }
    }

    package func userActivates(_ pid: pid_t, bundleID: String? = "test.fake.app") {
        precondition(pid < 0, "A fake app uses a negative pid, so no AX call reaches a real app")
        state.withLockUnchecked { state in
            state.apps[pid] = state.apps[pid] ?? bundleID
            state.front = pid
        }
    }

    package func setResizable(_ id: CGWindowID, _ resizable: Bool) {
        state.withLockUnchecked { state in state.windowList[id]?.resizable = resizable }
    }

    package func setTitle(_ id: CGWindowID, _ title: String?) {
        state.withLockUnchecked { state in state.windowList[id]?.title = title }
    }

    package func userMoves(_ id: CGWindowID, to frame: CGRect) {
        state.withLockUnchecked { state in state.windowList[id]?.frame = frame }
    }

    package func element(_ id: CGWindowID) -> AXUIElement? { state.withLockUnchecked { $0.windowList[id]?.element } }

    package func frame(of id: CGWindowID) -> CGRect { state.withLockUnchecked { $0.windowList[id]?.frame ?? .null } }

    package var ids: Set<CGWindowID> { state.withLockUnchecked { state in Set(state.windowList.keys) } }

    package var writes: [Write] { state.withLockUnchecked { state in state.writeLog } }

    package var placementChecks: Int { state.withLockUnchecked { state in state.placementCheckCount } }

    package func clearWrites() { state.withLockUnchecked { state in state.writeLog = [] } }

    package func focused(in pid: pid_t) -> CGWindowID? { state.withLockUnchecked { state in state.focusedIn[pid] } }

    package var frontmost: pid_t? { state.withLockUnchecked { state in state.front } }

    package var cursorRefreshes: Int { state.withLockUnchecked { state in state.cursorRefreshCount } }

    package func holdScans() -> DispatchSemaphore {
        state.withLockUnchecked { state in
            let gate = DispatchSemaphore(value: 0)
            state.scanGate = gate
            return gate
        }
    }

    package func applications() -> [RunningApplicationSnapshot] {
        state.withLockUnchecked { state in
            state.apps.map { RunningApplicationSnapshot(pid: $0.key, bundleID: $0.value, regular: true, hidden: false) }
        }
    }

    package func desktop(known _: Set<CGWindowID>) -> WindowServerObservation {
        state.withLockUnchecked { state in
            let all = state.stacking.compactMap { state.windowList[$0] }
            let shown = all.filter { !$0.minimized }
            return WindowServerObservation(
                windows: shown.map { CGWindowInfo(id: $0.id, pid: $0.pid, bounds: $0.frame) },
                allWindows: all.map { CGWindowInfo(id: $0.id, pid: $0.pid, bounds: $0.frame) })
        }
    }

    package func scan(_ job: WindowScanner.Job,
                      discovered _: (WindowScanner.AppScan) -> Void) -> WindowScanner.AppScan {
        if let gate = state.withLockUnchecked({ state in state.scanGate }) {
            gate.wait()
            gate.signal()
        }
        return state.withLockUnchecked { state in
            var scan = WindowScanner.AppScan()
            let mine = state.stacking.compactMap { state.windowList[$0] }.filter { $0.pid == job.pid }
            if job.listWindows { scan.listed = mine.map(\.id) }
            for window in mine where job.listWindows || job.known[window.id] != nil {
                if window.minimized { scan.minimized.insert(window.id) }
                guard !window.minimized || job.known[window.id] != nil else { continue }
                scan.found[window.id] = .init(element: window.element, frame: window.frame, title: window.title,
                                              resizable: window.resizable,
                                              frameRevision: job.known[window.id]?.frameRevision)
            }
            scan.gone = Set(job.known.keys).subtracting(mine.map(\.id))
            return scan
        }
    }

    package func focusedWindow(pid: pid_t) -> FocusReader.Result {
        state.withLockUnchecked { .focused($0.focusedIn[pid]) }
    }

    package func screens() -> [Screen] { state.withLockUnchecked { state in state.screenList } }

    package func currentSpace(display _: String) -> UInt64 { state.withLockUnchecked { UInt64($0.desktop) } }

    package func isRunning(_ pid: pid_t) -> Bool { state.withLockUnchecked { state in state.apps[pid] != nil } }

    package func frontmostPID() -> pid_t? { state.withLockUnchecked { state in state.front } }

    package func frame(of window: Window) -> CGRect { frame(of: window.id) }

    package func setPosition(_ window: Window, _ point: CGPoint) -> Bool {
        state.withLockUnchecked { state in
            guard state.windowList[window.id] != nil else { return false }
            state.windowList[window.id]?.frame.origin = point
            state.writeLog.append(.position(window.id, point))
            return true
        }
    }

    package func setSize(_ window: Window, _ size: CGSize) -> Bool {
        state.withLockUnchecked { state in
            guard let fake = state.windowList[window.id], fake.resizable else { return false }
            state.windowList[window.id]?.frame.size = CGSize(width: max(size.width, fake.minSize.width),
                                                       height: max(size.height, fake.minSize.height))
            state.writeLog.append(.size(window.id, size))
            return true
        }
    }

    package func blocksPlacement(_ window: Window) -> Bool {
        state.withLockUnchecked { state in
            state.placementCheckCount += 1
            return state.windowList[window.id]?.minimized ?? true
        }
    }

    package func suspendEnhancedUI(_: pid_t) -> Bool { false }

    package func resumeEnhancedUI(_: pid_t) {}

    package func focus(_ window: Window, ifCurrent: () -> Bool) {
        guard ifCurrent() else { return }
        userFocuses(window.id)
    }

    package func refreshCursor() {
        let observer = state.withLockUnchecked { state in
            state.cursorRefreshCount += 1
            return state.onCursorRefresh
        }
        observer?()
    }

    package func observeCursorRefresh(_ observer: (() -> Void)?) {
        state.withLockUnchecked { state in state.onCursorRefresh = observer }
    }
}
