import DatabaseTypes
public struct EmptyOperationPayload: DatabaseWireValue, Hashable {
    public init() {}

    public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {}

    public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self.init()
    }
}
