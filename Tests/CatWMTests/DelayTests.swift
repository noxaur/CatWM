import CatWMKit
import Foundation
import Testing

@Suite @MainActor struct DelayTests {
    @Test func scheduleReplacesPendingWork() {
        var ran: [String] = []
        var items: [DispatchWorkItem] = []
        let delay = Delay { _, item in items.append(item) }
        delay.schedule(after: 1) { ran.append("a") }
        delay.schedule(after: 2) { ran.append("b") }
        #expect(delay.isPending)
        #expect(items.count == 2)
        #expect(items[0].isCancelled)
        items[0].perform()
        items[1].perform()
        #expect(ran == ["b"])
        #expect(!delay.isPending)
    }

    @Test func cancelDropsPendingWork() {
        var ran = false
        var item: DispatchWorkItem?
        let delay = Delay { _, next in item = next }
        delay.schedule(after: 1) { ran = true }
        #expect(delay.isPending)
        delay.cancel()
        #expect(!delay.isPending)
        item?.perform()
        #expect(ran == false)
        #expect(item?.isCancelled == true)
    }

    @Test func deinitCancelsPendingWork() {
        var ran = false
        var item: DispatchWorkItem?
        var delay: Delay? = Delay { _, next in item = next }
        delay?.schedule(after: 1) { ran = true }
        #expect(delay?.isPending == true)
        delay = nil
        item?.perform()
        #expect(ran == false)
        #expect(item?.isCancelled == true)
    }
}
