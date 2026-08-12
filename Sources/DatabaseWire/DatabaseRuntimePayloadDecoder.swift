import DatabaseKit
import DatabaseTypes

/// Bounded decoding for opaque state owned by database operation execution.
@_spi(DatabaseOperations)
public enum DatabaseRuntimePayloadDecoder {
    public static func decode<Value: DatabaseRuntimePayloadValue>(
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

    public static func decodeResult<Value: DatabaseRuntimePayloadValue>(
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
