import DatabaseTypes

public struct DatabaseWireRequestEnvelope: Sendable, Hashable {
    public let requestID: UInt64
    public let operation: DatabaseOperationIdentifier
    public let metadata: OperationRequestMetadata
    public let payload: ByteString

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
}
