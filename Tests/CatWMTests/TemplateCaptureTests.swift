import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite struct TemplateCaptureTests {
    @Test func minimizedWindowsCanReportADialogSubrole() {
        #expect(WindowKind.includes(subrole: kAXStandardWindowSubrole, minimized: false))
        #expect(WindowKind.includes(subrole: kAXStandardWindowSubrole, minimized: true))
        #expect(WindowKind.includes(subrole: kAXDialogSubrole, minimized: true))
        #expect(!WindowKind.includes(subrole: kAXDialogSubrole, minimized: false))
        #expect(!WindowKind.includes(subrole: "AXSheet", minimized: true))
        #expect(!WindowKind.includes(subrole: nil, minimized: true))
    }

    @Test func timeoutReturnsBeforeACaptureThatIgnoresCancellation() async {
        let slot = CaptureSlot<Int>()
        let pause = Gate()
        let calls = CaptureCounter()
        defer { pause.open() }
        let outcome = await slot.run(within: .milliseconds(80)) {
            calls.bump()
            await pause.wait()
            return 1
        }
        #expect(outcome == .timedOut)
        #expect(calls.value == 1)
        pause.open()
        await Gate.bounded { await slot.settled() }
        let next = await slot.run(within: .seconds(60)) {
            calls.bump()
            return 2
        }
        #expect(next == .finished(2))
        #expect(calls.value == 2)
    }

    @Test func cancellationReturnsWhileTheCaptureKeepsRunning() async {
        let slot = CaptureSlot<Int>()
        let pause = Gate()
        let entered = Gate()
        defer { pause.open() }
        let task = Task {
            await slot.run(within: .seconds(30)) {
                entered.open()
                await pause.wait()
                return 1
            }
        }
        await entered.wait()
        task.cancel()
        let outcome = await task.value
        #expect(outcome == .cancelled)
        #expect(await slot.run(within: .milliseconds(50)) { 9 } == .busy)
    }

    @Test func occupiedSlotDoesNotReuseTheEarlierCapture() async {
        let slot = CaptureSlot<Int>()
        let pause = Gate()
        let calls = CaptureCounter()
        defer { pause.open() }
        let entered = Gate()
        let first = Task {
            await slot.run(within: .seconds(60)) {
                calls.bump()
                entered.open()
                await pause.wait()
                return 1
            }
        }
        await entered.wait()
        let second = await slot.run(within: .seconds(60)) {
            calls.bump()
            await pause.wait()
            return 2
        }
        #expect(second == .busy)
        #expect(calls.value == 1)
        pause.open()
        #expect(await first.value == .finished(1))
        await Gate.bounded { await slot.settled() }
        let third = await slot.run(within: .seconds(60)) {
            calls.bump()
            return 3
        }
        #expect(third == .finished(3))
        #expect(calls.value == 2)
    }

    @Test func stalledEnumerationIsNotACompleteTemplate() throws {
        let first = app(pid: 1)
        let second = app(pid: 2)
        var reads: [pid_t] = []
        let batch = WindowWalk.collect(
            apps: [first, second],
            budget: 5,
            stop: { false },
            read: { app in
                reads.append(app.pid)
                return app.pid == first.pid ? .stalled : .windows([observed(id: 2)])
            }
        )
        #expect(reads == [first.pid])
        #expect(!batch.complete)
        #expect(throws: WindowManager.TemplateError.incomplete) {
            try TemplateCaptureAssembler.make(facts: facts(), batch: batch)
        }
    }

    @Test func deadlineAndCancellationStopTheWalkBeforeLaterApps() {
        let apps = [app(pid: 1), app(pid: 2)]
        var expiredReads: [pid_t] = []
        let expired = WindowWalk.collect(
            apps: apps,
            budget: 0,
            stop: { false },
            read: { app in
                expiredReads.append(app.pid)
                return .windows([observed(id: CGWindowID(app.pid))])
            }
        )
        #expect(expiredReads.isEmpty)
        #expect(!expired.complete)
        var stoppedReads: [pid_t] = []
        let stopped = WindowWalk.collect(
            apps: apps,
            budget: 5,
            stop: { true },
            read: { app in
                stoppedReads.append(app.pid)
                return .windows([observed(id: CGWindowID(app.pid))])
            }
        )
        #expect(stoppedReads.isEmpty)
        #expect(!stopped.complete)
    }

    @Test func completeWalkKeepsEveryAppThatResponds() {
        let frozen = Date(timeIntervalSince1970: 10)
        let batch = WindowWalk.collect(
            apps: [app(pid: 4), app(pid: 9)],
            budget: 5,
            now: { frozen },
            stop: { false },
            read: { app in .windows([observed(id: CGWindowID(app.pid), title: app.name)]) }
        )
        #expect(batch.complete)
        #expect(batch.windows.map(\.windowID) == [4, 9])
    }

    @Test func savedWindowsKeepOrderMinimizedMaximisedAndLayout() throws {
        var savedFacts = facts(order: [7, 3])
        savedFacts.fullscreen = ["desk": 3]
        savedFacts.fallbackFocus = 7
        let minimized = observed(id: 3, title: "Draft", minimized: true)
        let maximised = observed(id: 7, title: "Talk", maximised: true)
        let template = try TemplateCaptureAssembler.make(
            facts: savedFacts,
            batch: .init(windows: [minimized, maximised], focusedID: nil, complete: true)
        )
        #expect(template.tilingEnabled)
        #expect(template.displays[0].layout == "tall")
        #expect(template.displays[0].ratio == 0.65)
        #expect(template.displays[0].mainCount == 2)
        #expect(template.windows.map(\.windowID) == [7, 3])
        #expect(template.windows[0].maximised)
        #expect(!template.windows[0].minimized)
        #expect(template.windows[0].focused)
        #expect(template.windows[1].minimized)
        #expect(template.windows[1].fullscreen)
        #expect(template.windows[1].document == "file:///tmp/draft.txt")
    }

    @Test func hiddenWorkspacesAndOtherSpacesStayOutUnlessMaximised() throws {
        var savedFacts = facts()
        savedFacts.hiddenWorkspaceWindows = [8, 7]
        let hidden = observed(id: 8, title: "Hidden")
        let maximised = observed(id: 7, title: "Show", maximised: true)
        let elsewhere = observed(id: 9, title: "Away", spaces: [99])
        let current = observed(id: 3, title: "Here", minimized: true)
        let template = try TemplateCaptureAssembler.make(
            facts: savedFacts,
            batch: .init(windows: [hidden, maximised, elsewhere, current], focusedID: 3, complete: true)
        )
        #expect(template.windows.map(\.windowID) == [3, 7])
        #expect(template.windows[0].focused)
    }

    @Test func maximisedOnItsOwnSpaceIsIncludedInTheTemplate() throws {
        var savedFacts = facts(order: [3, 7])
        savedFacts.hiddenWorkspaceWindows = [7]
        let natural = CGRect(x: 40, y: 40, width: 600, height: 400)
        savedFacts.naturalFrames = [7: natural]
        let template = try TemplateCaptureAssembler.make(
            facts: savedFacts,
            batch: .init(windows: [
                observed(id: 3, title: "Here"),
                observed(id: 7, title: "Presentation", maximised: true, spaces: [99]),
                observed(id: 9, title: "Other Desktop", spaces: [100])
            ], focusedID: 3, complete: true)
        )
        #expect(template.windows.map(\.windowID) == [3, 7])
        #expect(template.windows.last?.maximised == true)
        #expect(template.windows.last?.frame == natural)
    }

    @Test func maximisedUsesTheNaturalFrameAndFloatingFollowsTheVisibleFrame() throws {
        var savedFacts = facts()
        savedFacts.virtualWorkspaces = false
        savedFacts.naturalFrames = [
            5: CGRect(x: 0, y: 0, width: 1000, height: 800),
            6: CGRect(x: 1, y: 1, width: 900, height: 700)
        ]
        savedFacts.monitorForTiled = [1: "desk"]
        savedFacts.knownFloating = [1: false, 2: true]
        let maximised = observed(id: 5, frame: CGRect(x: 12, y: 12, width: 40, height: 40), maximised: true)
        let normal = observed(id: 6, frame: CGRect(x: 30, y: 40, width: 300, height: 200))
        let tiled = observed(id: 1, frame: CGRect(x: 1100, y: 20, width: 200, height: 200))
        let floating = observed(id: 2, frame: CGRect(x: 1100, y: 20, width: 200, height: 200))
        let template = try TemplateCaptureAssembler.make(
            facts: savedFacts,
            batch: .init(windows: [maximised, normal, tiled, floating], focusedID: nil, complete: true)
        )
        #expect(template.windows.first { $0.windowID == 5 }?.frame == CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(template.windows.first { $0.windowID == 6 }?.frame == CGRect(x: 30, y: 40, width: 300, height: 200))
        #expect(template.windows.first { $0.windowID == 1 }?.display == "desk")
        #expect(template.windows.first { $0.windowID == 2 }?.display == "lap")
    }

    @Test func emptyAndIncompleteCapturesDoNotBecomeTemplates() {
        #expect(throws: WindowManager.TemplateError.empty) {
            try TemplateCaptureAssembler.make(facts: facts(), batch: .init(windows: [], focusedID: nil, complete: true))
        }
        #expect(throws: WindowManager.TemplateError.incomplete) {
            try TemplateCaptureAssembler.make(
                facts: facts(),
                batch: .init(windows: [observed(id: 3)], focusedID: nil, complete: false)
            )
        }
    }
}

private func app(pid: pid_t) -> AppSnapshot {
    AppSnapshot(pid: pid, bundleID: "com.example.\(pid)", name: "App \(pid)", launchDate: nil)
}

private func observed(
    id: CGWindowID,
    title: String = "Window",
    frame: CGRect = CGRect(x: 40, y: 40, width: 600, height: 400),
    minimized: Bool = false,
    maximised: Bool = false,
    spaces: [UInt64] = [1]
) -> ObservedWindow {
    ObservedWindow(
        pid: 20, bundleID: "com.example.editor", appName: "Editor", title: title,
        document: title == "Draft" ? "file:///tmp/draft.txt" : nil, frame: frame, minimized: minimized,
        maximised: maximised, resizable: true, windowID: id, launchDate: Date(timeIntervalSince1970: 100),
        spaces: spaces
    )
}

private func facts(order: [CGWindowID] = []) -> TemplateCaptureFacts {
    TemplateCaptureFacts(
        tilingEnabled: true,
        displays: [
            .init(
                id: "desk", name: "Desk", frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                visible: CGRect(x: 0, y: 24, width: 1000, height: 776), isMain: true, layout: "tall",
                ratio: 0.65, mainCount: 2
            ),
            .init(
                id: "lap", name: "Laptop", frame: CGRect(x: 1000, y: 0, width: 800, height: 600),
                visible: CGRect(x: 1000, y: 24, width: 800, height: 576), isMain: false, layout: "floating",
                ratio: 0.5, mainCount: 1
            )
        ],
        fullscreen: [:], order: order, currentSpaces: [1], hiddenWorkspaceWindows: [], monitorForTiled: [:],
        virtualWorkspaces: true, knownFloating: [:], naturalFrames: [:], fallbackFocus: nil
    )
}
