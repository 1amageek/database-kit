import DatabaseTypes
public struct DatabaseWireResponseEnvelope: Sendable, Hashable {
    public let requestID: UInt64
    public let operation: DatabaseOperationIdentifier
    public let payload: DatabaseWireResponsePayload

    public init(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        payload: DatabaseWireResponsePayload
    ) {
        self.requestID = requestID
        self.operation = operation
        self.payload = payload
    }
}
