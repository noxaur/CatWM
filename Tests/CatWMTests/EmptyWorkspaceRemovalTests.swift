import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

@MainActor @Suite(.serialized) struct EmptyWorkspaceRemovalTests {
    private final class Removals { var spaces: [UInt64] = [] }

    private func makeManager(_ removals: Removals) async -> WindowManager {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let scanner = WindowScanner(readDesktop: { _ in
            WindowServerObservation(allWindows: [CGWindowInfo(id: 1, pid: 1, bounds: .zero)], spaces: [1: [1]])
        }, readApplications: { [] })
        await withCheckedContinuation { continuation in
            scanner.observeDesktop(known: [1]) { continuation.resume() }
        }
        let manager = WindowManager(backend: fake, config: .parse(defaultText), scanner: scanner)
        manager.config.virtualWorkspaces = true
        manager.config.removesEmptyWorkspaces = true
        manager.desktops.nativeCatalog.synchronize([.init(id: screen.uuid, spaces: [1, 2, 3])])
        manager.desktopRemover = { space, _ in removals.spaces.append(space) }
        return manager
    }

    @Test func aWorkspaceSwitchedToDuringTheSweepSurvivesIt() async {
        let removals = Removals()
        let manager = await makeManager(removals)
        manager.desktopRemover = { space, screen in
            removals.spaces.append(space)
            manager.nativeDesktop.request(.init(request: .init(workspace: "2", display: screen.uuid, space: 2)))
        }
        manager.releaseEmptyWorkspaces()
        #expect(await poll(2, every: 10_000_000) { !manager.nativeDesktop.isBusy && !removals.spaces.isEmpty })
        #expect(removals.spaces == [3])
    }

    @Test func aNewerSwitchReplacesAnOlderOneThatStillHasToCreateItsDesktop() async {
        let removals = Removals()
        let manager = await makeManager(removals)
        let display = manager.backend.screens().first?.uuid ?? ""
        manager.nativeDesktop.request(.init(request: .init(workspace: "1", display: display, space: 1)))
        manager.showNativeWorkspace("9", focusing: nil, focus: false, quiet: true)
        #expect(manager.nativeDesktop.machine.pendingWorkspaces == ["9"])
        manager.nativeDesktop.request(.init(request: .init(workspace: "2", display: display, space: 2)))
        #expect(manager.nativeDesktop.machine.pendingWorkspaces == ["2"])
        #expect(manager.nativeDesktop.machine.queue.isEmpty)
        #expect(await poll(2, every: 10_000_000) { !manager.nativeDesktop.isBusy })
    }

    @Test func anUntargetedEmptyWorkspaceIsStillRemoved() async {
        let removals = Removals()
        let manager = await makeManager(removals)
        manager.releaseEmptyWorkspaces()
        let removed = await poll(2, every: 10_000_000) { removals.spaces.contains(3) }
        #expect(removed)
    }
}
