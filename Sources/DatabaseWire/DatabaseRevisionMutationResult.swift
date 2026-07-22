public struct DatabaseRevisionMutationResult: DatabaseWireValue, Hashable {
    public let commitVersion: UInt64
    public let revision: UInt64

    public init(commitVersion: UInt64, revision: UInt64) {
        self.commitVersion = commitVersion
        self.revision = revision
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt64(commitVersion)
        writer.writeUInt64(revision)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            commitVersion: try reader.readUInt64(),
            revision: try reader.readUInt64()
        )
    }
}
