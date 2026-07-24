import DatabaseTypes

/// Canonical SHA-256 digest of a completed job response payload.
public struct DatabaseJobResultDigest:
    DatabaseWireValue,
    Hashable {
    public static let byteCount = 32

    public let bytes: ByteString

    public init(
        _ bytes: ByteString
    ) throws(DatabaseWireError) {
        guard bytes.count == Self.byteCount else {
            throw .invalidDigestLength(
                actual: bytes.count,
                expected: Self.byteCount
            )
        }
        self.bytes = bytes
    }

    public init(
        _ bytes: [UInt8]
    ) throws(DatabaseWireError) {
        try self.init(ByteString(bytes))
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard bytes.count == Self.byteCount else {
            throw .invalidDigestLength(
                actual: bytes.count,
                expected: Self.byteCount
            )
        }
        writer.writeUnframedBytes(bytes)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        try self.init(
            reader.readUnframedBytes(count: Self.byteCount)
        )
    }

    /// Detaches the fixed-size digest from a potentially much larger frame owner.
    public func detached() -> DatabaseJobResultDigest {
        DatabaseJobResultDigest(validatedBytes: bytes.detached())
    }

    fileprivate init(validatedBytes: ByteString) {
        self.bytes = validatedBytes
    }
}

/// Incrementally computes the canonical digest used by `job.result`.
///
/// The digest input is the ASCII domain `JOPI`, the job family in big-endian
/// order, the kind UTF-8 length and bytes, the ASCII domain `JRST`, and the
/// response payload bytes in page order.
public struct DatabaseJobResultDigestAccumulator: Sendable {
    private static let identifierDomain: ByteString = [0x4a, 0x4f, 0x50, 0x49]
    private static let resultDomain: ByteString = [0x4a, 0x52, 0x53, 0x54]

    private var sha256: SHA256Accumulator

    public init(operation: DatabaseJobOperationIdentifier) {
        var sha256 = SHA256Accumulator()
        Self.identifierDomain.withUnsafeBytes { bytes in
            sha256.update(bytes)
        }
        var family = operation.family.rawValue.bigEndian
        withUnsafeBytes(of: &family) { bytes in
            sha256.update(bytes)
        }
        let kindByteCount = UInt32(operation.kind.utf8.count)
        var encodedKindByteCount = kindByteCount.bigEndian
        withUnsafeBytes(of: &encodedKindByteCount) { bytes in
            sha256.update(bytes)
        }
        sha256.update(utf8: operation.kind)
        Self.resultDomain.withUnsafeBytes { bytes in
            sha256.update(bytes)
        }
        self.sha256 = sha256
    }

    public mutating func update(_ bytes: ByteString) {
        bytes.withUnsafeBytes { source in
            sha256.update(source)
        }
    }

    public consuming func finalize() -> DatabaseJobResultDigest {
        DatabaseJobResultDigest(validatedBytes: sha256.finalize())
    }
}
