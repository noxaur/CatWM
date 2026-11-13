import CatWMFakes
@testable import CatWMKit
import CoreGraphics
import Foundation
import Testing

@Suite struct MotionQualityTests {
    private let desired = CGRect(x: 100, y: 100, width: 400, height: 300)

    @Test func aWindowOnItsOutlineHasNoErrorSpillOrGap() {
        let sample = MotionQuality.Sample(desired: desired, actual: desired, filled: false)
        #expect(sample.error == 0 && sample.spill == 0 && sample.gap == 0)
    }

    @Test func aWiderWindowSpillsAndANarrowerOneLeavesAGap() {
        let wide = MotionQuality.Sample(desired: desired, actual: desired.insetBy(dx: -6, dy: 0), filled: false)
        #expect(wide.spill == 6 && wide.gap == 0 && wide.error == 6)
        let narrow = MotionQuality.Sample(desired: desired, actual: CGRect(x: 100, y: 100, width: 390, height: 280),
                                          filled: false)
        #expect(narrow.spill == 0 && narrow.gap == 20 && narrow.error == 20)
    }

    @Test func aFillHidesTheGapButNotTheSpill() {
        let actual = CGRect(x: 90, y: 100, width: 380, height: 300)
        let sample = MotionQuality.Sample(desired: desired, actual: actual, filled: true)
        #expect(sample.spill == 10 && sample.gap == 0 && sample.error == 30)
    }

    @Test func lagIsTheTimeTheTrajectoryTookToReachTheActualEdge() {
        let frame = { (time: Double) in CGRect(x: 1000 * time, y: 0, width: 100, height: 100) }
        let lag = MotionQuality.lag(at: 0.1, actual: frame(0.075), span: 0...0.2, frame: frame)
        #expect(abs((lag ?? 0) - 0.025) < 2e-4)
        let ahead = MotionQuality.lag(at: 0.1, actual: frame(0.11), span: 0...0.2, frame: frame)
        #expect(abs((ahead ?? 0) + 0.01) < 2e-4)
    }

    @Test func lagFollowsTheFastestEdgeAndSkipsSlowMotion() {
        let frame = { (time: Double) in CGRect(x: 10 * time, y: 0, width: 100 + 500 * time, height: 100) }
        let lag = MotionQuality.lag(at: 0.1, actual: CGRect(x: 1, y: 0, width: 140, height: 100), span: 0...0.2,
                                    frame: frame)
        #expect(abs((lag ?? 0) - 0.0196) < 2e-4)
        let still = { (_: Double) in CGRect(x: 0, y: 0, width: 100, height: 100) }
        #expect(MotionQuality.lag(at: 0.1, actual: still(0), span: 0...0.2, frame: still) == nil)
    }

    @Test func aWindowThatHasNotMovedLagsByTheElapsedTime() {
        let frame = { (time: Double) in CGRect(x: 1000 * time, y: 0, width: 100, height: 100) }
        let lag = MotionQuality.lag(at: 0.05, actual: frame(0), span: 0...0.2, frame: frame)
        #expect(abs((lag ?? 0) - 0.05) < 2e-4)
    }

    @Test func summaryReportsPercentilesPerApp() throws {
        var quality = MotionQuality()
        for width in stride(from: 401.0, through: 420, by: 1) {
            quality.add(.init(desired: desired, actual: CGRect(x: 100, y: 100, width: width, height: 300),
                              filled: false, lag: 0.01), pid: -100)
        }
        quality.add(.init(desired: desired, actual: desired, filled: true), pid: -101)
        let one = try #require(quality.summary(-100))
        #expect(one.samples == 20 && one.error.p50 == 10 && one.error.p95 == 19 && one.error.max == 20)
        #expect(one.lag?.p50 == 0.01)
        let all = try #require(quality.summary())
        #expect(all.samples == 21 && all.filled == 1)
        #expect(quality.summary(-102) == nil)
    }
}

@Suite struct MotionMeasureTests {
    @Test func overshootCountsOnlyMovingEdgesThatPassTheirTarget() {
        let from = CGRect(x: 0, y: 0, width: 100, height: 100), target = CGRect(x: 50, y: 0, width: 100, height: 100)
        #expect(MotionQuality.overshoot(target.offsetBy(dx: 4, dy: 0), from: from, to: target) == 4)
        #expect(MotionQuality.overshoot(target.offsetBy(dx: -4, dy: 0), from: from, to: target) == 0)
        #expect(MotionQuality.overshoot(target.offsetBy(dx: 0, dy: 3), from: from, to: target) == 0)
    }

    @Test func stutterIsTheVelocityErrorOfOneFrame() {
        let start = CGRect(x: 0, y: 0, width: 100, height: 100)
        let even = MotionQuality.stutter(actual: (start, start.offsetBy(dx: 10, dy: 0)),
                                         desired: (start.offsetBy(dx: 10, dy: 0), start.offsetBy(dx: 20, dy: 0)))
        #expect(even == 0)
        let hitch = MotionQuality.stutter(actual: (start, start),
                                          desired: (start.offsetBy(dx: 10, dy: 0), start.offsetBy(dx: 20, dy: 0)))
        #expect(hitch == 10)
    }
}

@MainActor @Suite struct MotionBenchTests {
    @Test func anInstantAppTracksTheTrajectory() async throws {
        let result = try #require(await MotionBench.measure(MotionBench.ratio(), .instant, mode: .live))
        let quality = try #require(result.quality)
        #expect(quality.samples > 3)
        #expect(quality.error.max < 1)
        #expect(quality.tail?.max == 0)
        print("instant: \(quality.text)")
    }

    @Test func aSlowAppLagsAndColorFillHidesTheGapOfARatioChange() async throws {
        let fixed = MotionBench.Profile.named("fixed")
        let live = try #require(await MotionBench.measure(MotionBench.ratio(), fixed, mode: .live)?.quality)
        let fill = try #require(await MotionBench.measure(MotionBench.ratio(), fixed, mode: .colorFill)?.quality)
        #expect(live.gap.max > 0)
        #expect(fill.filled > 0)
        #expect(fill.gap.max <= live.gap.max)
    }

    @Test func aLeadLearnedOnOneMoveTracksASlowAppOnTheNext() async throws {
        for profile in ["fixed", "slow-resize"] {
            for scene in MotionBench.moves {
                let warm = try #require(await MotionBench.measure(scene, .named(profile), mode: .live, warm: true)?
                    .quality)
                #expect(warm.error.p95 < 2, "\(scene.name) \(profile)")
                #expect(warm.overshoot.max < 1, "\(scene.name) \(profile)")
                #expect((warm.tail?.max ?? 1) < 0.02, "\(scene.name) \(profile)")
            }
        }
    }

    @Test func colorFillDoesNotEngageWhenTheTopEdgeMoves() async throws {
        for scene in [MotionBench.stackOpen, MotionBench.swap] {
            let fill = try #require(await MotionBench.measure(scene, .named("fixed"), mode: .colorFill)?.quality)
            #expect(fill.filled == 0, "\(scene.name)")
        }
    }

    @Test func baseline() async {
        var lines = ["| move | profile | run | mode | error px p50/p95/max | lag ms p50/p95/max | spill px p50/p95/max "
            + "| gap px p50/p95/max | stutter px p50/p95/max | overshoot px max | tail ms p50/max | tick ms avg/max |",
                     "|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for scene in MotionBench.moves {
            for profile in MotionBench.Profile.all {
                for warm in [false, true] {
                    for mode in MotionBench.Mode.allCases where mode == .live || scene.name == "ratio" {
                        guard let result = await MotionBench.measure(scene, profile, mode: mode, warm: warm),
                              let quality = result.quality else { continue }
                        let average = result.ticks.total / Double(max(1, result.ticks.count))
                        let cells = [scene.name, profile.name, warm ? "warm" : "cold", mode.rawValue,
                                     Self.text(quality.error), quality.lag.map { Self.text($0, 1000) } ?? "-",
                                     Self.text(quality.spill), Self.text(quality.gap),
                                     quality.stutter.map { Self.text($0) } ?? "-",
                                     String(format: "%.1f", quality.overshoot.max),
                                     quality.tail.map { String(format: "%.0f/%.0f", $0.p50 * 1000, $0.max * 1000) }
                                         ?? "-",
                                     String(format: "%.3f/%.3f", average * 1000, result.ticks.max * 1000)]
                        lines.append("| " + cells.joined(separator: " | ") + " |")
                    }
                }
            }
        }
        for rows in [1, 3, 6] {
            for mode in MotionBench.Mode.allCases {
                guard let result = await MotionBench.measure(MotionBench.ratio(rows: rows), .named("fixed"), mode: mode)
                else { continue }
                lines.append("| ratio-\(rows * 2)w | fixed | \(mode.rawValue) | tick \(result.ticks.text) |")
            }
        }
        print(lines.joined(separator: "\n"))
    }

    private static func text(_ spread: MotionQuality.Spread, _ scale: Double = 1) -> String {
        String(format: "%.1f/%.1f/%.1f", spread.p50 * scale, spread.p95 * scale, spread.max * scale)
    }
}
