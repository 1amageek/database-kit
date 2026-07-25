import DatabaseTypes
public struct OperationRequestMetadata: Sendable, Hashable {
    public let traceID: String?
    public let idempotencyKey: String?

    public init(traceID: String? = nil, idempotencyKey: String? = nil) {
        self.traceID = traceID
        self.idempotencyKey = idempotencyKey
    }

    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try writer.writeOptionalString(traceID)
        try writer.writeOptionalString(idempotencyKey)
    }

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self.init(
            traceID: try reader.readOptionalString(),
            idempotencyKey: try reader.readOptionalString()
        )
    }
}
