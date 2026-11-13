import CatWMFakes
import QuartzCore
import Testing

@MainActor @Test func advancingRunsEachTimerAtItsOwnDueTime() {
    let clock = FakeClock()
    var ran: [CFTimeInterval] = []
    clock.delay(0.12) {
        ran.append(clock.now())
        clock.delay(0.10) { ran.append(clock.now()) }
    }
    clock.delay(0.30) { ran.append(clock.now()) }
    clock.advance(by: 0.5)
    #expect(ran.map { ($0 * 100).rounded() / 100 } == [0.12, 0.22, 0.30])
    #expect(clock.now() == 0.5)
}
