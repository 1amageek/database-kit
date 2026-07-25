import DatabaseTypes
public struct EmptyOperationPayload: WireValue, Hashable {
    public init() {}

    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {}

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self.init()
    }
}
