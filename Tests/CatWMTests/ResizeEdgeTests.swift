import CatWMFakes
@testable import CatWMKit
import CoreGraphics
import Testing

@Suite struct ResizeEdgeTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test(arguments: [AnimationCurve.linear, .easeOut, .bounce])
    func growingAndShrinkingKeepTheOtherEdgeStill(_ curve: AnimationCurve) throws {
        let right = CGRect(x: 910, y: 38, width: 800, height: 600)
        let wider = CGRect(x: 850, y: 38, width: 860, height: 600)
        let narrower = CGRect(x: 980, y: 38, width: 730, height: 600)
        let left = CGRect(x: 40, y: 38, width: 700, height: 600)
        let taller = CGRect(x: 40, y: 38, width: 700, height: 760)
        try expectEdge(.maxX, from: right, target: wider, curve: curve, moving: \.minX)
        try expectEdge(.maxX, from: wider, target: narrower, curve: curve, moving: \.minX)
        try expectEdge(.minX, from: left, target: CGRect(x: 40, y: 38, width: 860, height: 600), curve: curve,
                       moving: \.width)
        try expectEdge(.minX, from: CGRect(x: 40, y: 38, width: 860, height: 600),
                       target: CGRect(x: 40, y: 38, width: 540, height: 600), curve: curve, moving: \.width)
        try expectEdge(.minY, from: left, target: taller, curve: curve, moving: \.height)
        try expectEdge(.maxY, from: CGRect(x: 40, y: 200, width: 700, height: 500),
                       target: CGRect(x: 40, y: 80, width: 700, height: 620), curve: curve, moving: \.minY)
    }

    @Test func carriedSpeedDoesNotDragTheEdgeThatStays() throws {
        let from = CGRect(x: 910, y: 38, width: 800, height: 600)
        let target = CGRect(x: 850, y: 38, width: 860, height: 600)
        let item = try item(from: from, target: target, curve: .easeOut, velocity: [240, 0, 0, 0])
        for step in 0...8 {
            let frame = item.frame(at: item.duration * Double(step) / 8, aligned: false)
            #expect(abs(frame.maxX - from.maxX) < 0.001)
        }
        let anchored = try item(from: CGRect(x: 40, y: 38, width: 500, height: 600),
                                target: CGRect(x: 40, y: 38, width: 680, height: 600),
                                curve: .easeOut, velocity: [180, 0, -90, 0])
        for step in 0...8 {
            let frame = anchored.frame(at: anchored.duration * Double(step) / 8, aligned: false)
            #expect(abs(frame.minX - 40) < 0.001)
        }
        #expect(anchored.frame(at: anchored.duration / 2, aligned: false).width > 500)
        #expect(abs(anchored.frame(at: anchored.duration, aligned: false).width - 680) < 0.001)
    }

    @Test func splitLayoutsMoveOnlyTheResizedEdge() throws {
        for layout in [Layout.tall, .tallRight, .twoPane, .twoPaneRight, .widescreenTall, .widescreenTallRight] {
            for ratio in [CGFloat(0.35), 0.65] {
                let before = try #require(layout.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1))
                let after = try #require(layout.frames(count: 3, in: screen, ratio: ratio, mainCount: 1))
                #expect(before[0].minY == after[0].minY && before[0].maxY == after[0].maxY, "\(layout)")
                if layout.ratioAxis?.fromStart == true {
                    #expect(abs(before[0].minX - after[0].minX) < 0.001, "\(layout) \(ratio)")
                    #expect(abs(before[1].maxX - after[1].maxX) < 0.001, "\(layout) \(ratio)")
                    #expect(abs(before[2].maxX - after[2].maxX) < 0.001, "\(layout) \(ratio)")
                } else {
                    #expect(abs(before[0].maxX - after[0].maxX) < 0.001, "\(layout) \(ratio)")
                    #expect(abs(before[1].minX - after[1].minX) < 0.001, "\(layout) \(ratio)")
                    #expect(abs(before[2].minX - after[2].minX) < 0.001, "\(layout) \(ratio)")
                }
                #expect(abs(after[0].width - before[0].width) > 1, "\(layout) \(ratio)")
            }
        }
        let before = try #require(Layout.wide.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1))
        let after = try #require(Layout.wide.frames(count: 3, in: screen, ratio: 0.65, mainCount: 1))
        #expect(abs(before[0].minY - after[0].minY) < 0.001)
        #expect(abs(before[2].maxY - after[2].maxY) < 0.001)
        #expect(abs(before[0].minX - after[0].minX) < 0.001 && abs(before[0].width - after[0].width) < 0.001)
    }

    @Test func dwindleWidthResizeKeepsTheFarEdge() {
        let area = CGRect(x: 0, y: 0, width: 1600, height: 900)
        var tree = DwindleTree()
        tree.sync([1, 2, 3])
        let before = tree.frames(in: area)
        tree.resize(at: 0, by: CGSize(width: 80, height: 0), in: area)
        let grown = tree.frames(in: area)
        #expect(abs(grown[0].minX - before[0].minX) < 0.001)
        #expect(abs(grown[0].width - before[0].width - 80) < 0.001)
        #expect(abs(grown[1].maxX - before[1].maxX) < 0.001)
        #expect(abs(grown[2].maxX - before[2].maxX) < 0.001)
        tree.resize(at: 1, by: CGSize(width: -80, height: 0), in: area)
        let shrunk = tree.frames(in: area)
        #expect(abs(shrunk[0].minX - grown[0].minX) < 0.001)
        #expect(abs(shrunk[1].maxX - grown[1].maxX) < 0.001)
        #expect(abs(shrunk[2].maxX - grown[2].maxX) < 0.001)
        #expect(shrunk[1].width < grown[1].width)
        #expect(shrunk[0].width > grown[0].width)
    }

    private func expectEdge(_ edge: Edge, from: CGRect, target: CGRect, curve: AnimationCurve,
                            moving: KeyPath<CGRect, CGFloat>? = nil) throws {
        let item = try item(from: from, target: target, curve: curve, velocity: nil)
        let stayed = edge.value(from)
        for step in 0...8 {
            let frame = item.frame(at: item.duration * Double(step) / 8, aligned: false)
            #expect(abs(edge.value(frame) - stayed) < 0.001)
            let aligned = item.frame(at: item.duration * Double(step) / 8)
            #expect(abs(edge.value(aligned) - stayed.rounded()) < 0.001)
        }
        if let moving {
            let mid = item.frame(at: item.duration / 2, aligned: false)
            #expect(mid[keyPath: moving] != from[keyPath: moving])
        }
    }

    private func item(from: CGRect, target: CGRect, curve: AnimationCurve,
                      velocity: [Double]?) throws -> Animator.Item {
        let backend = FakeBackend()
        let id = backend.addWindow(frame: from)
        let window = Window(id: id, element: try #require(backend.element(id)), pid: -140,
                            bundleID: nil, backend: backend)
        return Animator.Item(move: .init(window: window, to: target, bounds: from.union(target)), from: from,
                             start: 0, spec: .init(duration: 0.12, curve: curve, bounce: 0.4), velocity: velocity)
    }

    private enum Edge {
        case minX, maxX, minY, maxY

        func value(_ frame: CGRect) -> CGFloat {
            switch self {
            case .minX: frame.minX
            case .maxX: frame.maxX
            case .minY: frame.minY
            case .maxY: frame.maxY
            }
        }
    }
}
