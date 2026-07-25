import DatabaseTypes
public struct RevisionMutationResult: WireValue, Hashable {
    public let commitVersion: UInt64
    public let revision: UInt64

    public init(commitVersion: UInt64, revision: UInt64) {
        self.commitVersion = commitVersion
        self.revision = revision
    }

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt64(commitVersion)
        writer.writeUInt64(revision)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            commitVersion: try reader.readUInt64(),
            revision: try reader.readUInt64()
        )
    }
}
