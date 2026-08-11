import DatabaseTypes
protocol WireValue: Sendable {
    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError)
    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError)
}

/// A deterministic opaque payload owned by database operation execution.
///
/// Conformance does not create a DatabaseWire operation or expose a new
/// protocol identifier. Values travel only inside an already-declared opaque
/// byte field such as a continuation or persistent job state.
@_spi(DatabaseWireRuntime)
public protocol DatabaseRuntimePayloadValue: Sendable {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError)

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError)
}
