import DatabaseTypes
public struct DatabaseWireEnvelopeHeader: Sendable, Hashable {
    public let requestID: UInt64
    public let operation: DatabaseOperationIdentifier

    init(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier
    ) {
        self.requestID = requestID
        self.operation = operation
    }
}
