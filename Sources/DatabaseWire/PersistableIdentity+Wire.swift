public import DatabaseValue

extension PersistableIdentity {
    public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try DatabaseValueWireCodec.encode(self, into: &writer)
    }

    public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self = try DatabaseValueWireCodec.decodeIdentity(from: &reader)
    }
}
