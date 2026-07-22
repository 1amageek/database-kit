/// A synchronous destination for canonical RDF binary bytes.
///
/// Implementations must consume `bytes` before `write(_:)` returns. The
/// borrowed buffer is not valid outside that call. This protocol lets hashes,
/// storage keys, and wire frames consume the canonical representation without
/// first allocating an intermediate payload.
public protocol DatabaseRDFTermEncodingSink {
    mutating func write(_ byte: UInt8)

    mutating func write(_ bytes: UnsafeRawBufferPointer)
}
