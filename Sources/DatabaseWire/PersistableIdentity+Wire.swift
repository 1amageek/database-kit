public import DatabaseTypes

extension EntityReference {
    public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try FieldValueWireCodec.encode(self, into: &writer)
    }

    public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self = try FieldValueWireCodec.decodeReference(from: &reader)
    }
}
