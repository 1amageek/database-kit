/// Request-scoped resource limits enforced by database execution.
public struct ExecutionBudget: Sendable, Hashable {
    public let maximumRows: UInt32
    public let maximumWorkUnits: UInt64
    public let maximumIntermediateRows: UInt32
    public let maximumIntermediateBytes: UInt64
    public let timeoutMilliseconds: UInt32

    public init(
        maximumRows: UInt32 = 10_000,
        maximumWorkUnits: UInt64 = 1_000_000,
        maximumIntermediateRows: UInt32 = 10_000,
        maximumIntermediateBytes: UInt64 = 16 * 1_024 * 1_024,
        timeoutMilliseconds: UInt32 = 30_000
    ) {
        self.maximumRows = maximumRows
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumIntermediateRows = maximumIntermediateRows
        self.maximumIntermediateBytes = maximumIntermediateBytes
        self.timeoutMilliseconds = timeoutMilliseconds
    }
}
