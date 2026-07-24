import DatabaseTypes
public enum DatabaseErrorCategory: UInt8, Sendable, Hashable {
    case invalidRequest = 1
    case authentication = 2
    case authorization = 3
    case notFound = 4
    case conflict = 5
    case constraint = 6
    case resourceLimit = 7
    case unavailable = 8
    case internalFailure = 9

    public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        let rawValue = try reader.readUInt8()
        guard let value = Self(rawValue: rawValue) else {
            throw .invalidErrorCategory(rawValue)
        }
        self = value
    }

    public func encode(into writer: inout DatabaseWireWriter) {
        writer.writeUInt8(rawValue)
    }
}
