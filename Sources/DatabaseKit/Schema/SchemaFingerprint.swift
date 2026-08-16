import DatabaseTypes

/// Canonical SHA-256 identity of a complete schema declaration.
public struct SchemaFingerprint: Sendable, Hashable {
    public static let byteCount = SHA256Accumulator.digestByteCount

    public let bytes: ByteString

    public init(
        _ bytes: ByteString
    ) throws(SchemaFingerprintError) {
        guard bytes.count == Self.byteCount else {
            throw .invalidByteCount(
                actual: bytes.count,
                expected: Self.byteCount
            )
        }
        self.bytes = bytes
    }

    public init(
        _ bytes: [UInt8]
    ) throws(SchemaFingerprintError) {
        try self.init(ByteString(bytes))
    }

    public func detached() -> SchemaFingerprint {
        SchemaFingerprint(validatedBytes: bytes.detached())
    }

    /// Hashes one canonical schema representation without exposing its codec.
    public static func hashing(
        canonicalBytes: borrowing ByteString
    ) -> SchemaFingerprint {
        var accumulator = SHA256Accumulator()
        accumulator.update(canonicalBytes)
        return SchemaFingerprint(validatedBytes: accumulator.finalize())
    }

    private init(validatedBytes: ByteString) {
        self.bytes = validatedBytes
    }
}
