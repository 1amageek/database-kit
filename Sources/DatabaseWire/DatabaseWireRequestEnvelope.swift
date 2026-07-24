import DatabaseTypes
import DatabaseValue

public struct DatabaseWireRequestEnvelope: Sendable, Hashable {
    public let requestID: UInt64
    public let operation: DatabaseOperationIdentifier
    public let metadata: DatabaseRequestMetadata
    public let payload: ByteString

    public init(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        metadata: DatabaseRequestMetadata = DatabaseRequestMetadata(),
        payload: ByteString
    ) {
        self.requestID = requestID
        self.operation = operation
        self.metadata = metadata
        self.payload = payload
    }
}
