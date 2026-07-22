public import DatabaseValue

extension DatabaseValue {
    public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try DatabaseValueWireCodec.encode(self, into: &writer)
    }

    public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self = try DatabaseValueWireCodec.decodeValue(from: &reader)
    }
}
