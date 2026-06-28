/// Comparison operators for wire query predicates.
public enum DatabaseWireComparisonOperator: UInt8, Sendable, Hashable {
    case equal = 1
    case notEqual = 2
    case lessThan = 3
    case lessThanOrEqual = 4
    case greaterThan = 5
    case greaterThanOrEqual = 6
    case contains = 7

    public func encode(into writer: inout DatabaseWireBinaryWriter) {
        writer.writeUInt8(rawValue)
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        let tag = try reader.readUInt8()
        guard let value = DatabaseWireComparisonOperator(rawValue: tag) else {
            throw DatabaseWireError.unknownComparisonOperator(tag)
        }
        self = value
    }
}
