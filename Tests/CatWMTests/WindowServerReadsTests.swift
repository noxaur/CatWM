import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

struct WindowServerReadsTests {
    @Test func splitHandlesDoNotOccludeTilesButForegroundWindowsStillDo() {
        let tile = CGRect(x: 0, y: 25, width: 600, height: 875)
        let handle = CGRect(x: 591, y: 25, width: 18, height: 875)
        let floating = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames: [CGWindowID: CGRect] = [1: tile, 2: handle, 3: floating]
        #expect(WindowServerReads.obscured([1: tile], excluding: [2], order: [2, 1], frame: { frames[$0] }).isEmpty)
        #expect(WindowServerReads.obscured([1: tile], excluding: [2], order: [2, 3, 1], frame: { frames[$0] }) == [1])
        #expect(WindowServerReads.obscured([1: tile], excluding: [2], order: [2], frame: { frames[$0] }) == [1])
    }

    @Test func foregroundWindowsKeepTheirOcclusionDuringResize() {
        let tile = CGRect(x: 100, y: 100, width: 600, height: 400)
        let floating = CGRect(x: 150, y: 150, width: 200, height: 100)
        let frames: [CGWindowID: CGRect] = [1: tile, 2: floating]
        #expect(WindowServerReads.obscured([1: tile], order: [2, 1], frame: { frames[$0] }) == [1])
        #expect(WindowServerReads.obscured([1: tile], order: [1, 2], frame: { frames[$0] }).isEmpty)
        #expect(WindowServerReads.obscured([1: tile], moving: [2], order: [2, 1], frame: { frames[$0] }).isEmpty)
        #expect(WindowServerReads.obscured([1: tile.offsetBy(dx: 800, dy: 0)], order: [2, 1],
                                           frame: { frames[$0] }).isEmpty)
        #expect(WindowServerReads.obscured([1: tile], order: [2], frame: { frames[$0] }) == [1])
    }

    @Test func anObscuredWindowGivesUpOnlyItsOwnFill() {
        let left = CGRect(x: 0, y: 0, width: 700, height: 900), right = CGRect(x: 720, y: 0, width: 720, height: 900)
        let floating = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames: [CGWindowID: CGRect] = [3: floating]
        #expect(WindowServerReads.obscured([1: left, 2: right], moving: [1, 2], order: [3, 2, 1],
                                           frame: { frames[$0] }) == [1])
    }
}
