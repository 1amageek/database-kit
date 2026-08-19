import DatabaseKit

/// Canonical DatabaseWire representation shared by every `IndexType` field.
enum IndexTypeWireCodec {
    static func encode(
        _ type: IndexType,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch type {
        case .ordered:
            writer.writeUInt8(0)
        case .aggregate(let function):
            writer.writeUInt8(1)
            writer.writeUInt8(function.rawValue)
        case .updateCount:
            writer.writeUInt8(2)
        case .history:
            writer.writeUInt8(3)
        case .bitmap:
            writer.writeUInt8(4)
        case .leaderboard:
            writer.writeUInt8(5)
        case .vector:
            writer.writeUInt8(6)
        case .text(let type):
            writer.writeUInt8(7)
            writer.writeUInt8(type.rawValue)
        case .spatial:
            writer.writeUInt8(8)
        case .rank:
            writer.writeUInt8(9)
        case .graph(let type):
            writer.writeUInt8(10)
            writer.writeUInt8(type.rawValue)
        case .custom(let identifier):
            guard !identifier.isEmpty else {
                throw .emptyCustomIndexIdentifier
            }
            writer.writeUInt8(11)
            try writer.writeString(identifier)
        }
    }

    static func decode(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> IndexType {
        switch try reader.readUInt8() {
        case 0:
            return .ordered
        case 1:
            let rawValue = try reader.readUInt8()
            guard let function = AggregateFunctionType(rawValue: rawValue)
            else {
                throw .invalidValueTag(rawValue)
            }
            return .aggregate(function)
        case 2:
            return .updateCount
        case 3:
            return .history
        case 4:
            return .bitmap
        case 5:
            return .leaderboard
        case 6:
            return .vector
        case 7:
            let rawValue = try reader.readUInt8()
            guard let type = TextIndexType(rawValue: rawValue) else {
                throw .invalidValueTag(rawValue)
            }
            return .text(type)
        case 8:
            return .spatial
        case 9:
            return .rank
        case 10:
            let rawValue = try reader.readUInt8()
            guard let type = GraphIndexType(rawValue: rawValue) else {
                throw .invalidValueTag(rawValue)
            }
            return .graph(type)
        case 11:
            let identifier = try reader.readString()
            guard !identifier.isEmpty else {
                throw .emptyCustomIndexIdentifier
            }
            return .custom(identifier)
        case let tag:
            throw .invalidValueTag(tag)
        }
    }
}
