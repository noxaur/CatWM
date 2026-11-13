@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Testing

@Suite struct WorkspaceReconciliationTests {
    private let displayA = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let displayB = CGRect(x: 1000, y: 0, width: 1000, height: 800)

    private let spaceA = WorkspaceKey.space(display: "A", space: 1)
    private let spaceB = WorkspaceKey.space(display: "B", space: 2)

    private func observation(frames: [CGWindowID: CGRect], held: Set<CGWindowID> = []) -> WorkspaceObservation {
        WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1]),
                                        .init(id: "B", frame: displayB, space: 2, spaces: [2])],
                             frames: frames, present: Set(frames.keys), held: held)
    }

    @Test func fiftyWindowsProduceAReplayableSwitchPlan() {
        var model = WorkspaceModel()
        let elsewhere = WorkspaceKey.space(display: "A", space: 9)
        var frames: [CGWindowID: CGRect] = [:]
        for id in CGWindowID(1)...50 {
            model.assign(id, to: id <= 25 ? spaceA : elsewhere)
            model.order.append(id)
            frames[id] = id <= 25 ? displayA : CGRect(x: 1001, y: 1, width: 500, height: 400)
        }
        let facts = observation(frames: frames)
        let first = WorkspaceReconciliation.reconcile(facts, model: model, displayOf: [:])
        let replay = WorkspaceReconciliation.reconcile(facts, model: model, displayOf: [:])
        #expect(first.visible == Set(1...50))
        #expect(first.visible == replay.visible && first.model.workspaceOf == replay.model.workspaceOf)
        #expect((1...25).allSatisfy { first.model.workspaceOf[CGWindowID($0)] == spaceA })
        #expect((26...50).allSatisfy { first.model.workspaceOf[CGWindowID($0)] == spaceB })
        #expect(model.shown.isEmpty)
    }

    @Test func externalMovesJoinTheDestinationWorkspace() {
        var model = WorkspaceModel()
        model.assign(7, to: spaceA)
        let result = WorkspaceReconciliation.reconcile(observation(frames: [7: displayB]), model: model,
                                                       displayOf: [7: "A"])
        #expect(result.model.workspaceOf[7] == spaceB)
        #expect(result.displayOf[7] == "B")
    }

    @Test func inFlightMovesKeepTheirWorkspace() {
        var model = WorkspaceModel()
        model.assign(7, to: spaceA)
        let result = WorkspaceReconciliation.reconcile(
            observation(frames: [7: displayB], held: [7]), model: model, displayOf: [7: "A"]
        )
        #expect(result.model.workspaceOf[7] == spaceA)
        #expect(result.displayOf[7] == "A")
    }

    @Test func disconnectedDisplaysAndUnknownFramesUseTheRemainingDisplay() {
        var model = WorkspaceModel()
        let gone = WorkspaceKey.space(display: "gone", space: 3)
        model.virtualShown = ["gone": "1"]
        model.show(gone, on: "gone")
        model.assign(7, to: gone)
        let facts = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1])],
                                         frames: [7: .null, 8: .null], present: [7, 8], held: [])
        let result = WorkspaceReconciliation.reconcile(facts, model: model, displayOf: [:])
        #expect(result.model.shown == ["A": spaceA])
        #expect(result.model.virtualShown.isEmpty)
        #expect(result.model.workspaceOf[7] == spaceA)
        #expect(result.model.workspaceOf[8] == spaceA)
        #expect(result.visible == [7, 8])
    }

    @Test func rehomedTabsOnDifferentDisplaysSeparate() {
        var model = WorkspaceModel()
        for id: CGWindowID in [7, 8] { model.assign(id, to: "removed") }
        model.joinTab(8, onto: 7)
        let result = WorkspaceReconciliation.reconcile(
            observation(frames: [7: displayA, 8: displayB]), model: model, displayOf: [:])
        #expect(result.model.workspaceOf[7] == result.model.shown["A"])
        #expect(result.model.workspaceOf[8] == result.model.shown["B"])
        #expect(result.model.tabs.isEmpty)
        #expect(result.visible == [7, 8])
    }

    @Test func maximisedWindowsJoinTheWorkspaceOfTheirOwnSpace() {
        var model = WorkspaceModel()
        model.assign(7, to: spaceA)
        let facts = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1, 5])],
                                         frames: [8: displayA], present: [8], held: [], maximised: [7: 5])
        let result = WorkspaceReconciliation.reconcile(facts, model: model, displayOf: [:])
        let workspace = WorkspaceKey.space(display: "A", space: 5)
        #expect(result.model.workspaceOf[7] == workspace)
        #expect(result.model.maximisedHost[workspace] == 7)
        #expect(result.model.monitorOf[workspace] == "A")
        #expect(result.model.maximisedHost[spaceA] == nil)
        #expect(result.visible == [8])
    }

    @Test func maximisedWorkspaceIsShownWhileItsSpaceIsCurrent() {
        let facts = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 5, spaces: [1, 5])],
                                         frames: [:], present: [], held: [], maximised: [7: 5])
        let result = WorkspaceReconciliation.reconcile(facts, model: WorkspaceModel(), displayOf: [:])
        let workspace = WorkspaceKey.space(display: "A", space: 5)
        #expect(result.model.shown["A"] == workspace)
        #expect(result.model.isShown(result.model.workspaceOf[7]))
    }

    @Test func leavingMaximisedReturnsTheWindowToTheShownWorkspace() {
        var model = WorkspaceModel()
        let stale = WorkspaceKey.space(display: "A", space: 5)
        model.assign(7, to: stale)
        model.maximisedHost[stale] = 7
        let facts = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1])],
                                         frames: [7: displayA], present: [7], held: [])
        let result = WorkspaceReconciliation.reconcile(facts, model: model, displayOf: [:])
        #expect(result.model.workspaceOf[7] == spaceA)
        #expect(result.model.maximisedHost.isEmpty)
        #expect(result.visible == [7])
    }

    @Test func maximisedWindowsOnUnknownSpacesStayUnassigned() {
        let facts = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1])],
                                         frames: [:], present: [], held: [], maximised: [7: 9])
        let result = WorkspaceReconciliation.reconcile(facts, model: WorkspaceModel(), displayOf: [:])
        #expect(result.model.workspaceOf[7] == nil)
        #expect(result.model.maximisedHost.isEmpty)
    }

    @Test func aTabThatGoesMaximisedJoinsItsGroupAgainWhenItLeaves() {
        var model = WorkspaceModel()
        model.assign(7, to: spaceA); model.assign(8, to: spaceA)
        model.joinTab(8, onto: 7)
        let entering = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1, 5])],
                                            frames: [7: displayA], present: [7], held: [], maximised: [8: 5])
        var result = WorkspaceReconciliation.reconcile(entering, model: model, displayOf: [:])
        #expect(!result.model.tabs.isGrouped(8))
        let leaving = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1])],
                                           frames: [7: displayA, 8: displayA], present: [7, 8], held: [])
        result = WorkspaceReconciliation.reconcile(leaving, model: result.model, displayOf: [:])
        model = result.model
        #expect(model.rejoinMaximisedTabs { _ in true } == [8])
        #expect(model.tabs.group(of: 7)?.members == [7, 8])
    }
}
