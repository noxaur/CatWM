@testable import CatWMKit
import Testing

@Suite struct DesktopMachineTests {
    private typealias Machine = DesktopMachine

    private struct Node: Hashable {
        var machine = Machine()
        var nextID = 0
        var inputs = 0
        var answered: Set<Int> = []
    }

    private static let requests = [("1", "a", 1), ("2", "a", 2), ("1", "b", 3)].map {
        Machine.Switch(request: .init(workspace: $0.0, display: $0.1, space: UInt64($0.2)))
    }
    private static let works: [Machine.Work] = [
        .create("3", .show(.init())), .create("3", .window(7)), .create("3", .caller), .remove
    ]
    private static let maxJobs = 3
    private static let maxInputs = 5

    private static func inputs(_ node: Node) -> [Machine.Event] {
        var events = requests.flatMap { [Machine.Event.request($0), .beginGesture($0)] }
        events += [.scrub(0.5), .endGesture(commit: true), .endGesture(commit: false), .stop, .cancelWindow(7)]
        events += (0..<maxJobs).map { .cancel(job: $0) }
        if node.nextID < maxJobs { events += works.map { .enqueue(.init(id: node.nextID, work: $0)) } }
        return events
    }

    private static func completions(_ node: Node) -> [Machine.Event] {
        var events: [Machine.Event] = node.machine.slide == nil ? [] : [.slideFinished]
        if let held = node.machine.held {
            events += ([nil] + requests.map(\.request)).map { .finished(job: held.job.id, $0) }
        }
        return events
    }

    private static func step(_ node: Node, _ event: Machine.Event) -> Node {
        var next = node
        let before = Set(node.machine.queue.map(\.id))
        let effects = next.machine.send(event)
        if case .enqueue = event { next.nextID += 1 }
        if !completions(node).contains(event) { next.inputs += 1 }
        let after = Set(next.machine.queue.map(\.id))
        var answers: [Int] = []
        for effect in effects {
            switch effect {
            case .grant(let id), .drop(let id): answers.append(id)
            case .slide, .idle: break
            }
        }
        #expect(Set(answers).count == answers.count, "\(event) answered a job twice")
        #expect(next.answered.isDisjoint(with: answers), "\(event) answered a job again")
        let entered: Set<Int> = if case .enqueue(let job) = event { [job.id] } else { [] }
        #expect(before.union(entered).subtracting(after) == Set(answers), "\(event) lost or invented a job")
        next.answered.formUnion(answers)
        let slid = effects.contains { if case .slide = $0 { true } else { false } }
        #expect(slid == (next.machine.slide != nil && (node.machine.slide == nil || event == .slideFinished)))
        #expect(effects.contains(.idle) == (!node.machine.isIdle && next.machine.isIdle))
        return next
    }

    private static func check(_ node: Node) {
        let machine = node.machine
        #expect(!(machine.slide != nil && machine.held != nil), "a slide ran while a Desktop job held the lock")
        if machine.isIdle { #expect(machine.wanted == nil && machine.queue.isEmpty, "idle with work left") }
        if machine.isTracking { #expect(machine.wanted == machine.slide?.target, "a gesture tracked a stale target") }
        let shows = (machine.queue + [machine.held].compactMap { $0?.current == true ? $0?.job : nil })
            .filter { if case .create(_, .show) = $0.work { true } else { false } }
        #expect(shows.count + (machine.wanted == nil ? 0 : 1) <= 1, "two Desktop switches were pending")
        let ids = machine.queue.map(\.id) + [machine.held?.job.id].compactMap(\.self)
        #expect(Set(ids).count == ids.count, "a job was queued twice")
        #expect(Set(machine.queue.map(\.id)).isDisjoint(with: node.answered), "a queued job was already answered")
    }

    private static func settles(_ node: Node) -> Bool {
        var current = node
        for _ in 0...(maxJobs + 2) {
            if current.machine.isIdle { return current.answered.count == current.nextID }
            guard let event = completions(current).first else { return false }
            current = step(current, event)
        }
        return false
    }

    @Test func everyReachableStateKeepsTheInvariantsAndSettles() {
        var seen: Set<Node> = [Node()]
        var frontier = [Node()]
        while let node = frontier.popLast() {
            Self.check(node)
            #expect(Self.settles(node), "\(node.machine) never settles")
            let events = (node.inputs < Self.maxInputs ? Self.inputs(node) : []) + Self.completions(node)
            for event in events {
                let next = Self.step(node, event)
                if seen.insert(next).inserted { frontier.append(next) }
            }
        }
        #expect(seen.count > 1_000)
    }

    @Test func aReleasedSwipeKeepsItsProgressForTheLastFrame() {
        var machine = Machine()
        _ = machine.send(.beginGesture(Self.requests[0]))
        _ = machine.send(.scrub(0.7))
        _ = machine.send(.endGesture(commit: true))
        #expect(!machine.isTracking)
        #expect(machine.progress == 0.7)
    }

    @Test func aGestureInterruptionLeavesAKeyboardSwitchAlone() {
        var machine = Machine()
        let target = Self.requests[1]
        _ = machine.send(.request(target))
        _ = machine.send(.endGesture(commit: false))
        #expect(machine.wanted == target)
    }

    @Test func aSwitchWaitsForTheDesktopBeingCreated() {
        var machine = Machine()
        #expect(machine.send(.enqueue(.init(id: 0, work: .create("3", .window(7))))) == [.grant(0)])
        _ = machine.send(.request(Self.requests[0]))
        #expect(machine.slide == nil)
        #expect(machine.send(.beginGesture(Self.requests[1])).isEmpty)
        #expect(machine.send(.finished(job: 0, nil)) == [.slide(Self.requests[0])])
    }

    @Test func aCreatedWorkspaceIsShownUnlessANewerSwitchReplacedIt() {
        var machine = Machine()
        let created = Self.requests[1]
        _ = machine.send(.enqueue(.init(id: 0, work: .create("2", .show(.init(quiet: true))))))
        #expect(machine.send(.finished(job: 0, created.request))
            == [.slide(.init(request: created.request, options: .init(quiet: true)))])
        _ = machine.send(.slideFinished)
        _ = machine.send(.enqueue(.init(id: 1, work: .create("2", .show(.init())))))
        #expect(machine.pendingWorkspaces == ["2"])
        _ = machine.send(.request(Self.requests[0]))
        #expect(machine.pendingWorkspaces == ["1"])
        #expect(machine.send(.finished(job: 1, created.request)) == [.slide(Self.requests[0])])
    }
}
