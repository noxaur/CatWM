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

    @Test func aDirectJumpCancelsTheCorrectionOfAnEarlierStep() async throws {
        let (fake, manager) = await start()
        manager.goToSpace(3)
        let token = try #require(manager.nativeDesktop.machine.step?.token)
        fake.setDirectShortcuts(true)
        manager.goToSpace(1)
        #expect(fake.currentDesktop == 1)
        manager.correctSpace(token)
        #expect(fake.currentDesktop == 1)
    }

    @Test func aNewerStepStopsTheCorrectionOfAWindowDrag() async throws {
        let (fake, manager) = await start()
        manager.nativeDesktop.grab(true)
        manager.goToSpace(3, autoCorrect: false)
        let token = try #require(manager.nativeDesktop.machine.step?.token)
        manager.goToSpace(1)
        manager.holdUntilArrived(space: 3, release: .zero, restore: .zero, settle: 0, step: token)
        #expect(await fake.wait(manager) { !manager.nativeDesktop.isGrabbing })
        #expect(fake.currentDesktop == 1)
    }

    @Test func aDirectJumpKeepsCorrectionsForAWindowDrag() async throws {
        let (fake, manager) = await start()
        manager.goToSpace(3)
        let stale = try #require(manager.nativeDesktop.machine.step?.token)
        fake.setDirectShortcuts(true)
        manager.goToSpace(2, autoCorrect: false)
        let step = try #require(manager.nativeDesktop.machine.step)
        #expect(step.token != stale)
        #expect(step.goal.target == 1 && step.goal.corrections == 2)
    }

    @Test func aStepReplacesTheWaitingArrival() async {
        let (_, manager) = await start()
        var arrivals = 0
        #expect(manager.stepToSpace(4) { arrivals += 1 })
        manager.goToSpace(2)
        manager.activeSpaceChanged()
        #expect(arrivals == 0)
    }

    @Test func aDesktopThatArrivesTooLateRunsNothing() async {
        let (_, manager) = await start()
        var arrivals = 0
        #expect(manager.stepToSpace(4) { arrivals += 1 })
        manager.activeSpaceChanged(at: Date().addingTimeInterval(60))
        #expect(manager.nativeDesktop.machine.step == nil)
        manager.activeSpaceChanged()
        #expect(arrivals == 0)
    }
}
