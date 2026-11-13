@testable import CatWMKit
import CoreGraphics
import Testing

@Suite struct WindowLeadTests {
    private let period = 1.0 / 60
    private let start = CGRect(x: 0, y: 0, width: 800, height: 600)

    private func sample(_ lead: inout WindowLead, at now: Double, presentation: Double, period: Double? = nil,
                        bias: Double = 0, order: WindowLead.Order? = nil) -> WindowLead.Times {
        let plan = lead.plan(at: now, presentation: presentation, period: period ?? self.period, bias: bias,
                             order: order)
        lead.commit(plan)
        return plan.times
    }

    private func shows(_ lead: inout WindowLead, _ frames: [CGRect], from shown: Double, every step: Double? = nil,
                       period: Double? = nil) {
        for (index, frame) in frames.enumerated() {
            lead.observe(.init(frame: frame, shown: shown + Double(index) * (step ?? period ?? self.period),
                               period: period ?? self.period))
        }
    }

    private func moved(_ lead: inout WindowLead, to frame: CGRect, at finished: Double, cost: Double = 0) {
        lead.wrote(position: .init(frame.origin, seconds: cost, finished: finished), size: nil, learns: true)
    }

    private func resized(_ lead: inout WindowLead, to frame: CGRect, at finished: Double) {
        lead.wrote(position: nil, size: .init(CGPoint(x: frame.width, y: frame.height), seconds: 0,
                                              finished: finished), learns: true)
    }

    private func learned(delay: Double, resizes: Bool = false, times: Int = 1) -> WindowLead {
        var lead = WindowLead()
        for index in 0..<times {
            let shown = 1 + Double(index) * 3 * period
            let before = resizes ? CGRect(x: 0, y: 0, width: 800 + index, height: 600)
                : start.offsetBy(dx: CGFloat(index * 10), dy: 0)
            let after = resizes ? CGRect(x: 0, y: 0, width: 801 + index, height: 600) : before.offsetBy(dx: 10, dy: 0)
            if resizes { resized(&lead, to: after, at: shown + period - delay) } else {
                moved(&lead, to: after, at: shown + period - delay)
            }
            shows(&lead, [before, after], from: shown)
        }
        return lead
    }

    private func close(_ one: Double, _ other: Double) -> Bool { abs(one - other) < 1e-9 }

    @Test func aWindowWithNothingLearnedSamplesThePresentation() {
        var lead = WindowLead()
        #expect(sample(&lead, at: 1, presentation: 1 + period) == .init(position: 1 + period, size: 1 + period))
    }

    @Test func aRedrawDelayMovesTheSampleToTheVsyncTheWriteShowsAt() {
        var lead = WindowLead()
        let target = start.offsetBy(dx: 10, dy: 0)
        shows(&lead, [start], from: 1)
        moved(&lead, to: target, at: 1.005)
        shows(&lead, [start, target], from: 1 + period)
        let times = sample(&lead, at: 2, presentation: 2 + period, order: .positionOnly)
        #expect(close(times.position, 2 + 2 * period))
    }

    @Test func theSameDelayLeadsMoreFramesOnAFasterDisplay() {
        let fast = 1.0 / 120
        var lead = WindowLead()
        let target = start.offsetBy(dx: 10, dy: 0)
        shows(&lead, [start], from: 1, period: fast)
        moved(&lead, to: target, at: 1.001)
        shows(&lead, [start, start, start, target], from: 1 + fast, period: fast)
        let times = sample(&lead, at: 2, presentation: 2 + fast, period: fast, order: .positionOnly)
        #expect(close(times.position, 2 + 4 * fast))
    }

    @Test func positionAndSizeLearnSeparately() {
        var lead = learned(delay: 0.05, resizes: true, times: 3)
        let target = CGRect(x: 10, y: 0, width: 803, height: 600)
        moved(&lead, to: target, at: 1 + 9 * period - 0.005)
        shows(&lead, [CGRect(x: 0, y: 0, width: 803, height: 600), target], from: 1 + 8 * period)
        let delays = lead.delays(at: 1.2)
        #expect(close(delays[0] ?? 0, 0.005))
        #expect(close(delays[1] ?? 0, 0.05))
        let times = sample(&lead, at: 2, presentation: 2 + period)
        #expect(close(times.position, 2 + period))
        #expect(close(times.size, 2 + 3 * period))
    }

    @Test func anAxisWithNoSamplesBorrowsTheOtherAxisDelay() {
        var lead = learned(delay: 0.05, resizes: true, times: 1)
        #expect(lead.delays(at: 1.1)[0] == nil)
        let times = sample(&lead, at: 2, presentation: 2 + period)
        #expect(close(times.position, times.size))
    }

    @Test func aCallThatWaitsForTheOtherAxisFinishesLater() {
        var lead = WindowLead()
        lead.wrote(position: .init(.zero, seconds: 0.001, finished: 1),
                   size: .init(CGPoint(x: 800, y: 600), seconds: 0.012, finished: 1), learns: true)
        let first = lead.plan(at: 1, presentation: 1, period: period, order: .positionFirst).times
        let second = lead.plan(at: 1, presentation: 1, period: period, order: .sizeFirst).times
        #expect(first.position < second.position)
        #expect(first.size == second.size)
    }

    @Test func oneStalledSampleDoesNotMoveTheLead() {
        var lead = learned(delay: 0.03, times: 3)
        let base = 1 + 9 * period, before = start.offsetBy(dx: 30, dy: 0), after = before.offsetBy(dx: 10, dy: 0)
        moved(&lead, to: after, at: base - 0.2)
        shows(&lead, [before, after], from: base)
        #expect(close(lead.delays(at: base)[0] ?? 0, 0.03))
    }

    @Test func aStallIsCappedAtTheLeadLimit() {
        var lead = learned(delay: 0.5)
        #expect(close(lead.delays(at: 1.1)[0] ?? 0, MotionTiming.leadLimit))
        let times = sample(&lead, at: 2, presentation: 2 + period)
        #expect(times.position - 2 <= MotionTiming.leadLimit + 1e-9)
    }

    @Test func theLeadHoldsItsFrameNearABoundary() {
        var lead = WindowLead()
        let presentation = 1 + period
        let frames = [0.45, 1.3, 1.6, 0.4, 0.2].map { bias in
            ((sample(&lead, at: presentation, presentation: presentation, bias: bias * period).position
                - presentation) / period).rounded()
        }
        #expect(frames == [0, 1, 1, 1, 0])
    }

    @Test func aLateWriterSamplesTheVsyncItsWriteCanStillReach() {
        var lead = WindowLead()
        moved(&lead, to: start, at: 1, cost: 0.004)
        let times = sample(&lead, at: 1 + 1.5 * period, presentation: 1 + period, order: .positionOnly)
        #expect(close(times.position, 1 + 2 * period))
    }

    @Test func aWriterFarBehindSamplesNowNotAStaleFrame() {
        var lead = WindowLead()
        let times = sample(&lead, at: 60, presentation: 1, order: .positionOnly)
        #expect(times.position >= 60 - 1e-6)
    }

    @Test func aSizeTheWindowRefusesTeachesNothing() {
        var lead = WindowLead()
        let clamped = CGRect(x: 0, y: 0, width: 640, height: 600)
        shows(&lead, [start], from: 1)
        resized(&lead, to: CGRect(x: 0, y: 0, width: 576, height: 600), at: 1.005)
        shows(&lead, [start, clamped, clamped], from: 1 + period)
        #expect(lead.delays(at: 1.1)[1] == nil)
    }

    @Test func aDroppedFrameBetweenObservationsTeachesNothing() {
        var lead = WindowLead()
        let target = start.offsetBy(dx: 10, dy: 0)
        shows(&lead, [start], from: 1)
        moved(&lead, to: target, at: 1.005)
        shows(&lead, [start, target], from: 1, every: 2 * period)
        #expect(lead.delays(at: 1.1)[0] == nil)
    }

    @Test func anAxisThatStaysStillTeachesNothing() {
        var lead = WindowLead()
        for index in 0..<4 {
            moved(&lead, to: start, at: 1 + Double(index) * period + 0.001)
            shows(&lead, [start], from: 1 + Double(index + 1) * period)
        }
        #expect(lead.delays(at: 1.1)[0] == nil)
    }

    @Test func aLearnedDelayExpires() {
        let lead = learned(delay: 0.03)
        #expect(lead.delays(at: 1 + MotionTiming.leadMemory)[0] != nil)
        #expect(lead.delays(at: 1.1 + MotionTiming.leadMemory)[0] == nil)
    }

    @Test func aNewWindowStartsFromItsAppsDelays() {
        let lead = learned(delay: 0.03, times: 2)
        #expect(lead.inherited.delays(at: 1.1) == lead.delays(at: 1.1))
    }
}
