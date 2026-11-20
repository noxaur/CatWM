import CoreGraphics

package struct DesktopMachine: Hashable {
    package struct Request: Hashable {
        package let workspace: String
        package let display: String
        package let space: UInt64
    }

    package struct Options: Hashable {
        package var focus: CGWindowID?
        package var takesFocus = true
        package var quiet = false
        package var motion: String?

        package init(focus: CGWindowID? = nil, takesFocus: Bool = true, quiet: Bool = false, motion: String? = nil) {
            self.focus = focus
            self.takesFocus = takesFocus
            self.quiet = quiet
            self.motion = motion
        }
    }

    package struct Switch: Hashable {
        package let request: Request
        package var options = Options()
    }

    package struct Gesture: Hashable {
        package let direction: Double
        package var progress = 0.0
        package var released = false
    }

    package struct Slide: Hashable {
        package var target: Switch
        package var gesture: Gesture?
    }

    package enum Purpose: Hashable {
        case show(Options)
        case window(CGWindowID)
        case caller
    }

    package enum Work: Hashable {
        case create(String, Purpose)
        case remove
    }

    package struct Job: Hashable {
        package let id: Int
        package let work: Work
    }

    package struct Held: Hashable {
        package let job: Job
        package var current = true
    }

    package enum Event: Hashable {
        case request(Switch)
        case beginGesture(Switch, direction: Double)
        case scrub(Double)
        case endGesture(commit: Bool)
        case stop
        case slideFinished
        case enqueue(Job)
        case cancel(job: Int)
        case cancelWindow(CGWindowID)
        case finished(job: Int, Request?)
        case moveRequested(Int)
        case moveEnded(Int)
    }

    package enum Effect: Hashable {
        case slide(Switch)
        case grant(Int)
        case drop(Int)
        case startMove(Int)
        case idle
    }

    package private(set) var wanted: Switch?
    package private(set) var slide: Slide?
    package private(set) var held: Held?
    package private(set) var queue: [Job] = []
    package private(set) var moving: Set<Int> = []
    package private(set) var waitingMoves: [Int] = []

    package init() {}

    package var isIdle: Bool { slide == nil && held == nil }

    package var isTracking: Bool { slide?.gesture?.released == false }

    package var progress: Double { slide?.gesture?.progress ?? 0 }

    package func wants(_ target: Request) -> Bool {
        guard let wanted else { return false }
        return wanted.request == target || wanted.request.display != target.display
    }

    package var pendingWorkspaces: Set<String> {
        let shows = ([held].compactMap(\.self).filter(\.current).map(\.job) + queue).compactMap { job -> String? in
            guard case .create(let workspace, .show) = job.work else { return nil }
            return workspace
        }
        return Set(shows + [wanted?.request.workspace].compactMap(\.self))
    }

    package func creates(for window: CGWindowID) -> String? {
        let jobs = ([held].compactMap(\.self).filter(\.current).map(\.job) + queue)
        return jobs.lazy.compactMap { job -> String? in
            guard case .create(let workspace, .window(window)) = job.work else { return nil }
            return workspace
        }.first
    }

    package mutating func send(_ event: Event) -> [Effect] {
        let wasIdle = isIdle
        var effects: [Effect] = []
        switch event {
        case .request, .beginGesture, .scrub, .endGesture, .stop, .slideFinished: effects = slide(event)
        case .enqueue, .cancel, .cancelWindow, .finished: effects = job(event)
        case .moveRequested(let id):
            if held?.job.work == .remove { waitingMoves.append(id) } else { moving.insert(id) }
            if !waitingMoves.contains(id) { effects.append(.startMove(id)) }
        case .moveEnded(let id): moving.remove(id)
        }
        if held?.job.work != .remove, !waitingMoves.isEmpty {
            effects += waitingMoves.map { .startMove($0) }
            moving.formUnion(waitingMoves)
            waitingMoves = []
        }
        if isIdle {
            if let wanted {
                slide = Slide(target: wanted)
                effects.append(.slide(wanted))
            } else if let index = queue.firstIndex(where: { $0.work != .remove || moving.isEmpty }) {
                let next = queue.remove(at: index)
                held = Held(job: next)
                effects.append(.grant(next.id))
            }
        }
        if !wasIdle, isIdle { effects.append(.idle) }
        return effects
    }

    private mutating func slide(_ event: Event) -> [Effect] {
        var effects: [Effect] = []
        switch event {
        case .request(let target):
            releaseGesture()
            supersedeShows(&effects)
            wanted = target
            if slide?.target.request == target.request { slide?.target = target }
        case .beginGesture(let target, let direction):
            guard isIdle else { break }
            wanted = target
            slide = Slide(target: target, gesture: Gesture(direction: direction))
            effects.append(.slide(target))
        case .scrub(let value):
            guard isTracking, let direction = slide?.gesture?.direction else { break }
            slide?.gesture?.progress = min(1, max(0, value * direction))
        case .endGesture(let commit):
            guard isTracking else { break }
            releaseGesture()
            if !commit { wanted = nil }
        case .stop:
            releaseGesture()
            supersedeShows(&effects)
            wanted = nil
        default:
            guard let finished = slide else { break }
            slide = nil
            if wanted?.request == finished.target.request { wanted = nil }
        }
        return effects
    }

    private mutating func job(_ event: Event) -> [Effect] {
        var effects: [Effect] = []
        switch event {
        case .enqueue(let job):
            guard !queue.contains(where: { $0.id == job.id }), held?.job.id != job.id else { break }
            if case .create(_, .show) = job.work {
                releaseGesture()
                supersedeShows(&effects)
                wanted = nil
            }
            queue.append(job)
        case .cancel(let id):
            dropQueued(&effects) { $0.id == id }
            if held?.job.id == id { held?.current = false }
        case .cancelWindow(let window):
            func matches(_ job: Job) -> Bool {
                if case .create(_, .window(window)) = job.work { return true }
                return false
            }
            dropQueued(&effects, where: matches)
            if let job = held?.job, matches(job) { held?.current = false }
        case .finished(let id, let created):
            guard let done = held, done.job.id == id else { break }
            held = nil
            if done.current, case .create(_, .show(let options)) = done.job.work, let created {
                wanted = Switch(request: created, options: options)
            }
        default: break
        }
        return effects
    }

    private mutating func releaseGesture() {
        if isTracking { slide?.gesture?.released = true }
    }

    private mutating func supersedeShows(_ effects: inout [Effect]) {
        func isShow(_ job: Job) -> Bool {
            if case .create(_, .show) = job.work { return true }
            return false
        }
        dropQueued(&effects, where: isShow)
        if let job = held?.job, isShow(job) { held?.current = false }
    }

    private mutating func dropQueued(_ effects: inout [Effect], where matches: (Job) -> Bool) {
        effects += queue.filter(matches).map { .drop($0.id) }
        queue.removeAll(where: matches)
    }
}
