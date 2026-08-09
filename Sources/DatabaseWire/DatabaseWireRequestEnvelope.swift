import DatabaseTypes

public struct DatabaseWireRequestEnvelope: Sendable, Hashable {
    public let requestID: UInt64
    public let operation: DatabaseOperationIdentifier
    public let target: DatabaseOperationTarget
    public let metadata: OperationRequestMetadata
    public let payload: ByteString

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
}
