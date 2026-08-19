import DatabaseTypes

/// Identifies one persistent job and the exact runtime operation that owns it.
public struct JobIdentity: WireValue, Hashable {
    public let jobID: DatabaseTypes.UUID
    public let operation: JobOperationIdentifier
    #if DATABASE_KIT_MULTI_BASE
    public let target: DatabaseOperationTarget
    #endif

    #if DATABASE_KIT_MULTI_BASE
    public init(
        jobID: DatabaseTypes.UUID,
        operation: JobOperationIdentifier,
        target: DatabaseOperationTarget
    ) {
        self.jobID = jobID
        self.operation = operation
        self.target = target
    }
    #else
    public init(
        jobID: DatabaseTypes.UUID,
        operation: JobOperationIdentifier
    ) {
        self.jobID = jobID
        self.operation = operation
    }
    #endif

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try jobID.encode(into: &writer)
        try operation.encode(into: &writer)
        #if DATABASE_KIT_MULTI_BASE
        try target.encode(into: &writer)
        #endif
    }

    #if DATABASE_KIT_MULTI_BASE
    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            jobID: try DatabaseTypes.UUID(from: &reader),
            operation: try JobOperationIdentifier(from: &reader),
            target: try DatabaseOperationTarget(from: &reader)
        )
    }
    #else
    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            jobID: try DatabaseTypes.UUID(from: &reader),
            operation: try JobOperationIdentifier(from: &reader)
        )
    }
    #endif
}
