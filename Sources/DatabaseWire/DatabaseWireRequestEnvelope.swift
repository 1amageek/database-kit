import DatabaseTypes

public struct DatabaseWireRequestEnvelope: Sendable, Hashable {
    public let requestID: UInt64
    public let operation: DatabaseOperationIdentifier
    #if DATABASE_KIT_MULTIPLE_BASES
    public let target: DatabaseOperationTarget
    #endif
    public let metadata: OperationRequestMetadata
    public let payload: ByteString

    #if DATABASE_KIT_MULTIPLE_BASES
    init(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        target: DatabaseOperationTarget,
        metadata: OperationRequestMetadata = OperationRequestMetadata(),
        payload: ByteString
    ) {
        self.requestID = requestID
        self.operation = operation
        self.target = target
        self.metadata = metadata
        self.payload = payload
    }
    #else
    init(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        metadata: OperationRequestMetadata = OperationRequestMetadata(),
        payload: ByteString
    ) {
        self.requestID = requestID
        self.operation = operation
        self.metadata = metadata
        self.payload = payload
    }
    #endif
}
