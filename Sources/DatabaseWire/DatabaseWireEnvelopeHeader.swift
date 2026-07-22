public struct DatabaseWireEnvelopeHeader: Sendable, Hashable {
    public let requestID: UInt64
    public let operation: DatabaseOperationIdentifier

    public init(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier
    ) {
        self.requestID = requestID
        self.operation = operation
    }
}
