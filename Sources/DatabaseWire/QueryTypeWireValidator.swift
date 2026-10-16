import DatabaseKit
import DatabaseTypes

/// A bounded encoded descriptor view. No composite descriptor owner is materialized.
struct QueryWireTypeView {
    enum Shape {
        case scalar(QueryColumnType)
        case array
        case composite(Int)
    }
    let start: DatabaseWireReader
    let shape: Shape
    let maximumNestingDepth: UInt64

    func arrayElement() throws(DatabaseWireError) -> QueryWireTypeView {
        guard case .array = shape else { throw .invalidQueryValue(.incompatibleType) }
        var reader = start
        try reader.beginNestedValue()
        guard try reader.readUInt8() == 20 else { throw .invalidQueryIRWireState }
        return try QueryTypeWireValidator.validate(from: &reader)
    }

    func columns() throws(DatabaseWireError) -> QueryWireColumnCursor {
        guard case .composite(let count) = shape else { throw .invalidQueryValue(.incompatibleType) }
        var reader = start
        try reader.beginNestedValue()
        guard try reader.readUInt8() == 26, try reader.readCount() == count else { throw .invalidQueryIRWireState }
        return QueryWireColumnCursor(reader: reader, count: count)
    }
}

struct QueryWireColumnCursor {
    struct Column {
        let number: UInt32
        let name: ByteString
        let type: QueryWireTypeView
        let isNullable: Bool
    }
    var reader: DatabaseWireReader
    let count: Int
    var index = 0

    mutating func next() throws(DatabaseWireError) -> Column {
        guard index < count else { throw .invalidQueryIRWireState }
        let number = try reader.readUInt32()
        let name = try reader.validateQueryStringBytes()
        let type = try QueryTypeWireValidator.columnType(from: &reader)
        let nullable = try reader.readBool()
        index += 1
        return Column(number: number, name: name, type: type, isNullable: nullable)
    }
}

enum QueryWireExpectedType {
    case declared(QueryColumnType)
    case encoded(QueryWireTypeView)

    var scalar: QueryColumnType? {
        switch self {
        case .declared(let type):
            switch type { case .sql(.array), .sql(.composite): return nil; default: return type }
        case .encoded(let view):
            if case .scalar(let type) = view.shape { return type }
            return nil
        }
    }

    func arrayElement() throws(DatabaseWireError) -> Self {
        switch self {
        case .declared(.sql(.array(let type))): return .declared(.sql(type))
        case .encoded(let view): return .encoded(try view.arrayElement())
        default: throw .invalidQueryValue(.incompatibleType)
        }
    }
}

/// Validates descriptor bytes using one cursor per open type and the caller's ledger.
enum QueryTypeWireValidator {
    private enum Step {
        case type(isElement: Bool, depth: UInt64)
        case columns(remaining: Int, ordinal: UInt32, depth: UInt64)
        case nullability
        case end
    }

    static func validate(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryWireTypeView {
        let start = reader
        var shape: QueryWireTypeView.Shape?
        var steps: [Step] = [.type(isElement: false, depth: 1)]
        var maximumDepth: UInt64 = 0
        var open = 0
        defer { reader.abandonNestedValues(open) }
        while let step = steps.popLast() {
            switch step {
            case .type(let isElement, let depth):
                maximumDepth = max(maximumDepth, depth)
                try reader.beginNestedValue()
                open += 1
                steps.append(.end)
                let tag = try reader.readUInt8()
                switch tag {
                case 20:
                    guard !isElement else { throw .invalidQueryValue(.incompatibleType) }
                    if shape == nil { shape = .array }
                    steps.append(.type(isElement: true, depth: depth + 1))
                case 26:
                    let count = try reader.readCount()
                    if shape == nil { shape = .composite(count) }
                    steps.append(.columns(remaining: count, ordinal: 1, depth: depth))
                default:
                    let type = try QueryIRDataTypeWireCodec.decodeScalar(tag: tag, from: &reader)
                    guard QueryValueValidator.accepts(.primitive(.null), type: .sql(type)) else {
                        throw .invalidQueryValue(.incompatibleType)
                    }
                    if shape == nil { shape = .scalar(.sql(type)) }
                }
            case .columns(let remaining, let ordinal, let depth):
                guard remaining > 0 else { continue }
                let number = try reader.readUInt32()
                guard number == ordinal else { throw .invalidQueryValue(.invalidColumnNumber(number)) }
                _ = try reader.validateQueryStringBytes()
                steps.append(.columns(remaining: remaining - 1, ordinal: ordinal &+ 1, depth: depth))
                steps.append(.nullability)
                maximumDepth = max(maximumDepth, depth + 2)
                switch try reader.readUInt8() {
                case 0:
                    let raw = try reader.readString()
                    guard FieldSchemaType(rawValue: raw) != nil else { throw .invalidQueryValue(.incompatibleType) }
                    _ = try reader.readBool()
                case 1: steps.append(.type(isElement: false, depth: depth + 2))
                case let tag: throw .invalidValueTag(tag)
                }
            case .nullability: _ = try reader.readBool()
            case .end:
                try reader.endNestedValue()
                open -= 1
            }
        }
        guard let shape else { throw .invalidQueryIRWireState }
        return QueryWireTypeView(start: start, shape: shape, maximumNestingDepth: maximumDepth)
    }

    static func columnType(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryWireTypeView {
        switch try reader.readUInt8() {
        case 0:
            let start = reader
            let raw = try reader.readString()
            guard let kind = FieldSchemaType(rawValue: raw) else { throw .invalidQueryValue(.incompatibleType) }
            return QueryWireTypeView(start: start, shape: .scalar(.primitive(kind, isArray: try reader.readBool())), maximumNestingDepth: 1)
        case 1: return try validate(from: &reader)
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private enum ComparisonStep {
        case type(QueryWireTypeView, QueryWireExpectedType)
        case declaredColumns(QueryWireColumnCursor, QueryCompositeColumns, Int)
        case encodedColumns(QueryWireColumnCursor, QueryWireColumnCursor)
    }

    static func matches(_ view: QueryWireTypeView, expected: QueryWireExpectedType) throws(DatabaseWireError) -> Bool {
        var steps: [ComparisonStep] = [.type(view, expected)]
        while let step = steps.popLast() {
            switch step {
            case .type(let view, let expected):
                switch view.shape {
                case .scalar(let actual):
                    guard expected.scalar == actual else { return false }
                case .array:
                    let child: QueryWireExpectedType
                    switch expected {
                    case .declared(.sql(.array(let type))): child = .declared(.sql(type))
                    case .encoded(let encoded):
                        guard case .array = encoded.shape else { return false }
                        child = .encoded(try encoded.arrayElement())
                    default: return false
                    }
                    steps.append(.type(try view.arrayElement(), child))
                case .composite(let count):
                    switch expected {
                    case .declared(.sql(.composite(let type))):
                        guard type.columns.count == count else { return false }
                        steps.append(.declaredColumns(try view.columns(), type.columns, 0))
                    case .encoded(let encoded):
                        guard case .composite(let otherCount) = encoded.shape, count == otherCount else { return false }
                        steps.append(.encodedColumns(try view.columns(), try encoded.columns()))
                    default: return false
                    }
                }
            case .declaredColumns(var cursor, let columns, let index):
                guard index < columns.count else { continue }
                let actual = try cursor.next()
                let expected = columns[index]
                guard actual.number == expected.number, actual.name.elementsEqual(expected.name.utf8),
                      actual.isNullable == expected.isNullable else { return false }
                steps.append(.declaredColumns(cursor, columns, index + 1))
                steps.append(.type(actual.type, .declared(expected.type)))
            case .encodedColumns(var left, var right):
                guard left.index < left.count else { continue }
                let actual = try left.next()
                let expected = try right.next()
                guard actual.number == expected.number, actual.name == expected.name,
                      actual.isNullable == expected.isNullable else { return false }
                steps.append(.encodedColumns(left, right))
                steps.append(.type(actual.type, .encoded(expected.type)))
            }
        }
        return true
    }
}
