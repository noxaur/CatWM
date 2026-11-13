import CatWMFakes
@testable import CatWMKit
import CoreGraphics
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct LayoutCapabilityTests {
    private nonisolated static let withoutMouseResize: Set<Layout> = [
        .middleWide, .fullscreen, .column, .row, .floating, .threeColumnMiddle
    ]
    private nonisolated static let resizesItsOwnSplits: Set<Layout> = [.dwindle]

    @Test func everyLayoutWithoutARatioAxisIsNamed() {
        #expect(Set(Layout.allCases.filter { $0.ratioAxis == nil })
            == Self.withoutMouseResize.union(Self.resizesItsOwnSplits))
    }

    @Test(arguments: Layout.allCases.filter { !withoutMouseResize.contains($0) })
    func aMouseResizeOfTheMainWindowMovesTheSplit(_ layout: Layout) async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let clock = FakeClock()
        let manager = fake.makeManager(clock: clock)
        (0..<3).forEach { _ in fake.addWindow() }
        manager.setLayout(layout, on: screen)
        #expect(await fake.settle(manager))
        clock.advance(by: 1)
        #expect(await fake.settle(manager))
        clock.advance(by: 1)
        let ids = manager.tiled(on: screen), main = ids[0]
        let before = ids.map(fake.frame(of:)), ratio = manager.state(for: screen).ratio
        let tree = manager.state(for: screen).dwindle
        let axis: (horizontal: Bool, fromStart: Bool) = Self.resizesItsOwnSplits.contains(layout)
            ? (true, true) : try #require(layout.ratioAxis)
        var grown = before[0]
        if layout == .bsp || axis.horizontal {
            grown.size.width += 100
            if !axis.fromStart { grown.origin.x -= 100 }
        } else {
            grown.size.height += 100
        }
        fake.userMoves(main, to: grown)
        manager.drags[main] = true
        manager.observeFrame(try #require(manager.windows[main]))
        manager.mouseUp()

        #expect(await fake.wait(manager) {
            manager.state(for: screen).ratio != ratio || manager.state(for: screen).dwindle != tree
        })
        #expect(await fake.settle(manager))
        let after = ids.map(fake.frame(of:))
        #expect(after[0] == grown)
        #expect(after[1] != before[1])
    }
}
