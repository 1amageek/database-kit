import DatabaseTypes

extension EntityReference {
    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try FieldValueWireCodec.encode(self, into: &writer)
    }

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self = try FieldValueWireCodec.decodeReference(from: &reader)
    }
}
