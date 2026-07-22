public import DatabaseValue

/// Identifies one persistent job and the exact runtime operation that owns it.
public struct DatabaseJobIdentity: DatabaseWireValue, Hashable {
    public let jobID: DatabaseUUID
    public let operation: DatabaseJobOperationIdentifier

    public init(
        jobID: DatabaseUUID,
        operation: DatabaseJobOperationIdentifier
    ) {
        self.jobID = jobID
        self.operation = operation
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try jobID.encode(into: &writer)
        try operation.encode(into: &writer)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            jobID: try DatabaseUUID(from: &reader),
            operation: try DatabaseJobOperationIdentifier(from: &reader)
        )
    }
}
