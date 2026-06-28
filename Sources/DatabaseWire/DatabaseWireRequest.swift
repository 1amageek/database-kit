/// Top-level wire database request envelope.
public enum DatabaseWireRequest: Sendable, Hashable {
    case applySchema(DatabaseWireSchema)
    case putRecord(DatabaseWireRecord)
    case getRecord(typeName: String, id: String)
    case query(DatabaseWireQueryRequest)
    case vectorQuery(DatabaseWireVectorQueryRequest)

    public var operation: DatabaseWireOperation {
        switch self {
        case .applySchema:
            return .applySchema
        case .putRecord:
            return .putRecord
        case .getRecord:
            return .getRecord
        case .query:
            return .query
        case .vectorQuery:
            return .vectorQuery
        }
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        operation.encode(into: &writer)
        switch self {
        case .applySchema(let schema):
            try schema.encode(into: &writer)
        case .putRecord(let record):
            try record.encode(into: &writer)
        case .getRecord(let typeName, let id):
            try writer.writeString(typeName)
            try writer.writeString(id)
        case .query(let query):
            try query.encode(into: &writer)
        case .vectorQuery(let query):
            try query.encode(into: &writer)
        }
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        switch try DatabaseWireOperation(from: &reader) {
        case .applySchema:
            self = .applySchema(try DatabaseWireSchema(from: &reader))
        case .putRecord:
            self = .putRecord(try DatabaseWireRecord(from: &reader))
        case .getRecord:
            self = .getRecord(typeName: try reader.readString(), id: try reader.readString())
        case .query:
            self = .query(try DatabaseWireQueryRequest(from: &reader))
        case .vectorQuery:
            self = .vectorQuery(try DatabaseWireVectorQueryRequest(from: &reader))
        }
    }
}
