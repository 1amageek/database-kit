import DatabaseTypes

/// Canonical SHA-256 identity of the persisted database storage layout.
public struct DatabaseLayoutFingerprint: Sendable, Hashable {
    public static let byteCount = 32

    public let bytes: ByteString

    public init(_ bytes: ByteString) throws(DatabaseWireError) {
        guard bytes.count == Self.byteCount else {
            throw .invalidDigestLength(
                actual: bytes.count,
                expected: Self.byteCount
            )
        }
        self.bytes = bytes
    }

    public init(_ bytes: [UInt8]) throws(DatabaseWireError) {
        try self.init(ByteString(bytes))
    }

    func encode(
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

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        try self.init(reader.readUnframedBytes(count: Self.byteCount))
    }

    public func detached() -> Self {
        Self(validatedBytes: bytes.detached())
    }

    private init(validatedBytes: ByteString) {
        self.bytes = validatedBytes
    }
}

extension DatabaseLayoutFingerprint: WireValue {}
