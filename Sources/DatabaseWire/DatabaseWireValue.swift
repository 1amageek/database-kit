public protocol DatabaseWireValue: Sendable {
    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError)
    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError)
}
