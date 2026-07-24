import DatabaseTypes

extension DatabaseWireReader {
    public mutating func readOptionalString() throws(DatabaseWireError) -> String? {
        guard try readBool() else { return nil }
        return try readString()
    }

    public mutating func readOptionalBytes() throws(DatabaseWireError) -> ByteString? {
        guard try readBool() else { return nil }
        return try readBytes()
    }
}
