@testable import CatWM
import Testing

@Suite @MainActor struct TabStripBatchTests {
    @Test func anInstantUpdateStaysInstantWhenALaterUpdateInTheBatchIsAnimated() {
        let strips = TabStrips()
        var instants: [Bool] = []
        strips.onPerformUpdate = { instant, _ in instants.append(instant) }

        strips.batch {
            strips.update(instant: true)
            strips.update(instant: false)
        }
        strips.batch {
            strips.update(instant: false)
            strips.update(instant: true)
        }
        strips.batch {
            strips.update(instant: false)
            strips.update(instant: false)
        }
        strips.batch {
            strips.update(instant: true)
            strips.batch {
                strips.update(instant: false)
            }
        }

        #expect(instants == [true, true, false, true])
    }
}
