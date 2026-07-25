import DatabaseTypes

extension FieldObject {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try FieldValueWireCodec.encode(self, into: &writer)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self = try FieldValueWireCodec.decodeObject(from: &reader)
    }
}
