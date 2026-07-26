import DatabaseKit
import DatabaseTypes

/// Bounded decoding for opaque state owned by the database server runtime.
@_spi(DatabaseServer)
public enum ServerPayloadDecoder {
    public static func decode<Value: ServerPayloadValue>(
        _ type: Value.Type,
        from bytes: ByteString,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> Value {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let value = try Value(from: &reader)
        try reader.ensureFullyRead()
        return value
    }

    public static func decode(
        _ type: RDFQuad.Type,
        from bytes: ByteString,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> RDFQuad {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let value = try RDFQuad(from: &reader)
        try reader.ensureFullyRead()
        return value
    }

    public static func decodeResult<Value: ServerPayloadValue>(
        _ type: Value.Type,
        from bytes: ByteString,
        limits: DatabaseWireLimits = .default
    ) -> Result<Value, DatabaseWireError> {
        do {
            return .success(
                try decode(type, from: bytes, limits: limits)
            )
        } catch {
            return .failure(error)
        }
    }
}
