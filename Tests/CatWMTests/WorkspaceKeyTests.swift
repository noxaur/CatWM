@testable import CatWMKit
import Testing

@Suite struct WorkspaceKeyTests {
    @Test func aSpaceKeyIsNotACatWMWorkspace() {
        let key = WorkspaceKey.space(display: "ABC-123", space: 42)
        #expect(key == "space:ABC-123:42")
        #expect(key.hasPrefix(WorkspaceKey.spacePrefix))
        #expect(!WorkspaceKey.make("1", on: "ABC-123", perDisplay: true).hasPrefix(WorkspaceKey.spacePrefix))
    }

    @Test func aKeyHoldsItsDisplayOnlyWhenWorkspacesArePerDisplay() {
        #expect(WorkspaceKey.make("2", on: "left", perDisplay: true) == "left/2")
        #expect(WorkspaceKey.make("2", on: "left", perDisplay: false) == "2")
        #expect(WorkspaceKey.display("left/2") == "left")
        #expect(WorkspaceKey.display("2") == nil)
        #expect(WorkspaceKey.number("left/2") == "2")
        #expect(WorkspaceKey.number("2") == "2")
    }

    @Test func numbersReadFromTheLastPart() {
        #expect(WorkspaceKey.numeric("left/12") == 12)
        #expect(WorkspaceKey.numeric("web") == nil)
        #expect(WorkspaceKey.ordinal("left/12") == 12)
        #expect(WorkspaceKey.ordinal("web") == 0)
    }

    @Test func workspacesSortNumericallyThenByName() {
        #expect(["10", "web", "2", "1", "chat"].sorted(by: WorkspaceKey.precedes) == ["1", "2", "10", "chat", "web"])
        #expect(["b/10", "b/2"].sorted(by: WorkspaceKey.precedes) == ["b/2", "b/10"])
    }
}
