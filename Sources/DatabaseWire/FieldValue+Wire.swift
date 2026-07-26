import DatabaseTypes

@_spi(DatabaseServer)
public extension FieldValue {
    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try FieldValueWireCodec.encode(self, into: &writer)
    }

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self = try FieldValueWireCodec.decodeValue(from: &reader)
    }
}
