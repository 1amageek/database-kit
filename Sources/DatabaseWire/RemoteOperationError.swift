import DatabaseTypes

public struct RemoteOperationError: Error, Sendable, Hashable {
    public let category: OperationErrorCategory
    public let code: String
    public let message: String
    public let retryability: OperationRetryability
    public let details: FieldObject

    public init(
        category: OperationErrorCategory,
        code: String,
        message: String,
        retryability: OperationRetryability,
        details: FieldObject = FieldObject()
    ) {
        self.category = category
        self.code = code
        self.message = message
        self.retryability = retryability
        self.details = details
    }

    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        category.encode(into: &writer)
        try writer.writeString(code)
        try writer.writeString(message)
        retryability.encode(into: &writer)
        try details.encode(into: &writer)
    }

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        let category = try OperationErrorCategory(from: &reader)
        let code = try reader.readString()
        let message = try reader.readString()
        let retryability = try OperationRetryability(from: &reader)
        self.init(
            category: category,
            code: code,
            message: message,
            retryability: retryability,
            details: try FieldObject(from: &reader)
        )
    }
}
