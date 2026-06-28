/// Index family metadata for DatabaseKit wire runtime.
public enum DatabaseWireIndexKind: Sendable, Hashable {
    case scalar
    case vector
    case fullText
    case spatial
    case rank
    case permuted
    case graph
    case relationship
    case aggregation
    case version
    case bitmap
    case leaderboard
    case custom(String)

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        switch self {
        case .scalar:
            writer.writeUInt8(1)
        case .vector:
            writer.writeUInt8(2)
        case .fullText:
            writer.writeUInt8(3)
        case .spatial:
            writer.writeUInt8(4)
        case .rank:
            writer.writeUInt8(5)
        case .permuted:
            writer.writeUInt8(6)
        case .graph:
            writer.writeUInt8(7)
        case .relationship:
            writer.writeUInt8(8)
        case .aggregation:
            writer.writeUInt8(9)
        case .version:
            writer.writeUInt8(10)
        case .bitmap:
            writer.writeUInt8(11)
        case .leaderboard:
            writer.writeUInt8(12)
        case .custom(let identifier):
            writer.writeUInt8(255)
            try writer.writeString(identifier)
        }
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        let tag = try reader.readUInt8()
        switch tag {
        case 1:
            self = .scalar
        case 2:
            self = .vector
        case 3:
            self = .fullText
        case 4:
            self = .spatial
        case 5:
            self = .rank
        case 6:
            self = .permuted
        case 7:
            self = .graph
        case 8:
            self = .relationship
        case 9:
            self = .aggregation
        case 10:
            self = .version
        case 11:
            self = .bitmap
        case 12:
            self = .leaderboard
        case 255:
            self = .custom(try reader.readString())
        default:
            throw DatabaseWireError.unknownIndexKind(tag)
        }
    }
}
