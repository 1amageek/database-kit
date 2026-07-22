import DatabaseValue

extension FieldValue {
    public var asDatabaseValue: DatabaseValue {
        switch self {
        case .int64(let value):
            return .int64(value)
        case .uint64(let value):
            return .uint64(value)
        case .double(let value):
            return .double(value)
        case .string(let value):
            return .string(value)
        case .bool(let value):
            return .bool(value)
        case .data(let value):
            return .bytes(value)
        case .rdfTerm(let value):
            return .rdfTerm(value)
        case .null:
            return .null
        case .array(let values):
            return .array(values.map(\.asDatabaseValue))
        }
    }

    public init?(databaseValue: DatabaseValue) {
        switch databaseValue {
        case .null:
            self = .null
        case .bool(let value):
            self = .bool(value)
        case .int64(let value):
            self = .int64(value)
        case .uint64(let value):
            self = .uint64(value)
        case .double(let value):
            self = .double(value)
        case .string(let value):
            self = .string(value)
        case .bytes(let value):
            self = .data(value)
        case .rdfTerm(let value):
            self = .rdfTerm(value)
        case .array(let values):
            var converted: [FieldValue] = []
            converted.reserveCapacity(values.count)
            for value in values {
                guard let fieldValue = FieldValue(databaseValue: value) else {
                    return nil
                }
                converted.append(fieldValue)
            }
            self = .array(converted)
        case .decimal, .date, .timestamp, .uuid, .object, .reference:
            return nil
        }
    }
}
