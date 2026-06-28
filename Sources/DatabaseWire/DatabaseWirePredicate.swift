/// Wire query predicate tree.
public indirect enum DatabaseWirePredicate: Sendable, Hashable {
    case comparison(field: String, op: DatabaseWireComparisonOperator, value: DatabaseWireFieldValue)
    case and([DatabaseWirePredicate])
    case or([DatabaseWirePredicate])
    case not(DatabaseWirePredicate)

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        switch self {
        case .comparison(let field, let op, let value):
            writer.writeUInt8(1)
            try writer.writeString(field)
            op.encode(into: &writer)
            try value.encode(into: &writer)
        case .and(let predicates):
            writer.writeUInt8(2)
            try Self.write(predicates, into: &writer)
        case .or(let predicates):
            writer.writeUInt8(3)
            try Self.write(predicates, into: &writer)
        case .not(let predicate):
            writer.writeUInt8(4)
            try predicate.encode(into: &writer)
        }
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        let tag = try reader.readUInt8()
        switch tag {
        case 1:
            self = .comparison(
                field: try reader.readString(),
                op: try DatabaseWireComparisonOperator(from: &reader),
                value: try DatabaseWireFieldValue(from: &reader)
            )
        case 2:
            self = .and(try Self.readList(from: &reader))
        case 3:
            self = .or(try Self.readList(from: &reader))
        case 4:
            self = .not(try DatabaseWirePredicate(from: &reader))
        default:
            throw DatabaseWireError.unknownPredicate(tag)
        }
    }

    private static func write(
        _ predicates: [DatabaseWirePredicate],
        into writer: inout DatabaseWireBinaryWriter
    ) throws(DatabaseWireError) {
        try writer.writeCount(predicates.count)
        for predicate in predicates {
            try predicate.encode(into: &writer)
        }
    }

    private static func readList(
        from reader: inout DatabaseWireBinaryReader
    ) throws(DatabaseWireError) -> [DatabaseWirePredicate] {
        let count = try reader.readCount()
        var predicates: [DatabaseWirePredicate] = []
        predicates.reserveCapacity(count)
        for _ in 0..<count {
            predicates.append(try DatabaseWirePredicate(from: &reader))
        }
        return predicates
    }
}
