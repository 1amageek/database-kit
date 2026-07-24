import DatabaseTypes
import DatabaseValue

extension DatabaseSHACLPath: DatabaseWireValue {
    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.withNestedValue {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            switch self {
        case .predicate(let iri):
            writer.writeUInt8(1)
            try writer.writeString(iri)
        case .inverse(let path):
            writer.writeUInt8(2)
            try path.encode(into: &writer)
        case .sequence(let paths):
            writer.writeUInt8(3)
            try Self.encode(paths, into: &writer)
        case .alternative(let paths):
            writer.writeUInt8(4)
            try Self.encode(paths, into: &writer)
        case .zeroOrMore(let path):
            writer.writeUInt8(5)
            try path.encode(into: &writer)
        case .oneOrMore(let path):
            writer.writeUInt8(6)
            try path.encode(into: &writer)
        case .zeroOrOne(let path):
            writer.writeUInt8(7)
            try path.encode(into: &writer)
            }
        }
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self = try reader.withNestedValue {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> DatabaseSHACLPath in
            switch try reader.readUInt8() {
            case 1:
                return .predicate(try reader.readString())
            case 2:
                return .inverse(try DatabaseSHACLPath(from: &reader))
            case 3:
                return .sequence(try Self.decodePaths(from: &reader))
            case 4:
                return .alternative(try Self.decodePaths(from: &reader))
            case 5:
                return .zeroOrMore(try DatabaseSHACLPath(from: &reader))
            case 6:
                return .oneOrMore(try DatabaseSHACLPath(from: &reader))
            case 7:
                return .zeroOrOne(try DatabaseSHACLPath(from: &reader))
            case let tag:
                throw DatabaseWireError.invalidValueTag(tag)
            }
        }
    }

    private static func encode(
        _ paths: [DatabaseSHACLPath],
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeCount(paths.count)
        for path in paths {
            try path.encode(into: &writer)
        }
    }

    private static func decodePaths(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> [DatabaseSHACLPath] {
        let count = try reader.readCount()
        var paths: [DatabaseSHACLPath] = []
        paths.reserveCapacity(count)
        for _ in 0..<count {
            paths.append(try DatabaseSHACLPath(from: &reader))
        }
        return paths
    }
}
