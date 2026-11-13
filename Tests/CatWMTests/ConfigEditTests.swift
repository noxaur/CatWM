@testable import CatWMKit
import Testing

@Suite struct ConfigEditTests {
    private func replace(_ path: String, _ value: JSON, in source: String, line: Int) -> String? {
        ConfigEdit.replacing(path, with: value, in: source, near: line)
    }

    @Test func aStatementInsideAFunctionOrAConditionIsLeftAlone() {
        let source = """
        if (true) catwm.gaps.size = 8
        if (true) {
          catwm.gaps.size = 9
        }
        function setup() { catwm.gaps.size = 10 }
        """
        for line in 1...5 { #expect(replace("gaps.size", .int(1), in: source, line: line) == nil) }
    }

    @Test func aStatementAfterACallOrASemicolonIsEdited() {
        let source = "catwm.bind([\"alt\"], \"a\", \"sort\")\ncatwm.gaps.size = 8;\ncatwm.motion.enabled = true\n"
        #expect(replace("gaps.size", .int(1), in: source, line: 2)
            == "catwm.bind([\"alt\"], \"a\", \"sort\")\ncatwm.gaps.size = 1;\ncatwm.motion.enabled = true\n")
    }

    @Test func aComputedValueOrAnExpressionIsNotALiteral() {
        for text in ["catwm.gaps.size = base * 2", "catwm.gaps.size = 8 + 2", "catwm.gaps.size = f(1)",
                     "catwm.gaps.size = cond ? 1 : 2", "catwm.gaps.size += 2"] {
            #expect(replace("gaps.size", .int(1), in: text + "\n", line: 1) == nil)
        }
    }

    @Test func theLastWriteOnTheRecordedLineWins() {
        let source = "catwm.gaps.size = 4\ncatwm.gaps.size = 6\n"
        #expect(replace("gaps.size", .int(9), in: source, line: 1) == "catwm.gaps.size = 9\ncatwm.gaps.size = 6\n")
        #expect(replace("gaps.size", .int(9), in: source, line: 2) == "catwm.gaps.size = 4\ncatwm.gaps.size = 9\n")
    }

    @Test func aFieldInANestedGroupObjectIsFound() {
        let source = "catwm.features = {\n  windows: { tiling: true, tabs: false },\n  input: { keys: true },\n}\n"
        #expect(replace("features.windows.tabs", .bool(true), in: source, line: 1)
            == "catwm.features = {\n  windows: { tiling: true, tabs: true },\n  input: { keys: true },\n}\n")
    }

    @Test func aListIsReplacedWithTheWriterFormat() {
        let source = "catwm.floating.apps = [\"a\", \"b\"] // note\n"
        #expect(replace("floating.apps", .array([.string("c")]), in: source, line: 1)
            == "catwm.floating.apps = [\"c\"] // note\n")
    }

    @Test func stringsTemplatesCommentsAndRegexesDoNotConfuseTheScan() {
        let source = """
        const text = `catwm.gaps.size = 1 ${ "}" } \\` still`
        /* catwm.gaps.size = 2 */
        const re = /catwm.gaps.size = 3/g
        // catwm.gaps.size = 4
        catwm.gaps.size = 8
        """
        #expect(replace("gaps.size", .int(5), in: source, line: 5)?.hasSuffix("catwm.gaps.size = 5") == true)
    }

    @Test func theSettingsBlockIsCreatedOnceAndUpdatedInPlace() {
        let first = ConfigEdit.settings("gaps.size", .int(12), in: "import { catwm } from \"./catwm\"\n")
        #expect(first == "import { catwm } from \"./catwm\"\n\n// Settings\ncatwm.gaps.size = 12\n")
        let second = ConfigEdit.settings("motion.enabled", .bool(false), in: first)
        let third = ConfigEdit.settings("gaps.size", .int(14), in: second)
        #expect(third == "import { catwm } from \"./catwm\"\n\n// Settings\ncatwm.gaps.size = 14\n"
            + "catwm.motion.enabled = false\n")
    }

    @Test func aFileWithoutTheImportGetsOne() {
        #expect(ConfigEdit.settings("gaps.size", .int(1), in: "")
            == "import { catwm } from \"./catwm\"\n// Settings\ncatwm.gaps.size = 1\n")
    }
}
