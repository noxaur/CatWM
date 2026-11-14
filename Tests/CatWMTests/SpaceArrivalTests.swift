import CatWMFakes
@testable import CatWMKit
import Foundation
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct SpaceArrivalTests {
    private func start() async -> (FakeBackend, WindowManager) {
        let fake = FakeBackend()
        fake.addScreen()
        fake.setDesktops(4)
        let manager = fake.makeManager()
        await fake.settle(manager)
        return (fake, manager)
    }

    @Test func aMultiStepJumpRunsItsActionOnlyOnceTheTargetDesktopIsCurrent() async throws {
        let (fake, manager) = await start()
        var arrivals = 0
        #expect(manager.stepToSpace(4) { arrivals += 1 })
        #expect(fake.desktopSwitches == [2, 3, 4])
        #expect(arrivals == 0)
        manager.postKey(try #require(fake.stepShortcut(right: false)))
        manager.activeSpaceChanged()
        #expect(arrivals == 0)
        manager.postKey(try #require(fake.stepShortcut(right: true)))
        manager.activeSpaceChanged()
        #expect(arrivals == 1)
        manager.activeSpaceChanged()
        #expect(arrivals == 1)
    }

    @Test func aNewJumpReplacesTheWaitingOne() async {
        let (_, manager) = await start()
        var arrived: [Int] = []
        #expect(manager.stepToSpace(3) { arrived.append(3) })
        #expect(manager.stepToSpace(4) { arrived.append(4) })
        manager.activeSpaceChanged()
        #expect(arrived == [4])
    }

    @Test func aDesktopThatArrivesTooLateRunsNothing() async {
        let (_, manager) = await start()
        var arrivals = 0
        #expect(manager.stepToSpace(4) { arrivals += 1 })
        manager.activeSpaceChanged(at: Date().addingTimeInterval(60))
        #expect(manager.desktops.spaceArrival == nil)
        manager.activeSpaceChanged()
        #expect(arrivals == 0)
    }
}
