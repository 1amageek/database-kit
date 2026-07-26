import DatabaseTypes

/// Bounded encoding for opaque state owned by the database server runtime.
///
/// This SPI does not create operation identifiers or envelopes. It allows
/// server-owned continuations and persistent job state to share the canonical
/// scalar representation and limits used by DatabaseWire.
@_spi(DatabaseServer)
public enum ServerPayloadEncoder {
    public static func encode<Value: ServerPayloadValue>(
        _ value: Value,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) in
            try value.encode(into: &writer)
        }
    }
}
