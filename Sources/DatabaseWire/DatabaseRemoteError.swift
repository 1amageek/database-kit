import DatabaseTypes
import DatabaseValue

public struct DatabaseRemoteError: Error, Sendable, Hashable {
    public let category: DatabaseErrorCategory
    public let code: String
    public let message: String
    public let retryability: DatabaseRetryability
    public let details: FieldObject

    public init(
        category: DatabaseErrorCategory,
        code: String,
        message: String,
        retryability: DatabaseRetryability,
        details: FieldObject = FieldObject()
    ) {
        self.category = category
        self.code = code
        self.message = message
        self.retryability = retryability
        self.details = details
    }

    public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        category.encode(into: &writer)
        try writer.writeString(code)
        try writer.writeString(message)
        retryability.encode(into: &writer)
        try details.encode(into: &writer)
    }

    public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        let category = try DatabaseErrorCategory(from: &reader)
        let code = try reader.readString()
        let message = try reader.readString()
        let retryability = try DatabaseRetryability(from: &reader)
        self.init(
            category: category,
            code: code,
            message: message,
            retryability: retryability,
            details: try FieldObject(from: &reader)
        )
    }
}
