import Testing

@Suite struct GateTests {
    @Test func anOpenedGateLetsEveryWaiterThrough() async {
        let gate = Gate()
        gate.open()
        gate.block()
        await gate.wait()
        await gate.wait()
    }

    @Test func aGateThatNeverOpensRecordsAnIssueInsteadOfHanging() async {
        let gate = Gate(limit: .milliseconds(50))
        await withKnownIssue { await gate.wait() }
        withKnownIssue { gate.block() }
    }
}
