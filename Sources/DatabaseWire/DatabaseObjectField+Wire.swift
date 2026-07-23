public import DatabaseValue

extension DatabaseObjectField {
    public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try FieldValueWireCodec.encode(self, into: &writer)
    }

    public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self = try FieldValueWireCodec.decodeField(from: &reader)
    }
}
