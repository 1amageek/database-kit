import DatabaseTypes

/// Identifies one persistent job and the exact runtime operation that owns it.
public struct JobIdentity: WireValue, Hashable {
    public let jobID: DatabaseTypes.UUID
    public let operation: JobOperationIdentifier
    public let target: DatabaseOperationTarget

    public init(
        jobID: DatabaseTypes.UUID,
        operation: JobOperationIdentifier,
        target: DatabaseOperationTarget
    ) {
        self.jobID = jobID
        self.operation = operation
        self.target = target
    }

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try jobID.encode(into: &writer)
        try operation.encode(into: &writer)
        try target.encode(into: &writer)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            jobID: try DatabaseTypes.UUID(from: &reader),
            operation: try JobOperationIdentifier(from: &reader),
            target: try DatabaseOperationTarget(from: &reader)
        )
    }
}
