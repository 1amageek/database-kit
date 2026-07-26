/// A synchronous destination for canonical RDF binary bytes.
///
/// Implementations must consume `bytes` before `write(_:)` returns. The
/// borrowed buffer is not valid outside that call. This protocol lets a wire
/// frame consume the representation without first allocating an intermediate
/// payload.
protocol RDFTermWireSink {
    mutating func write(_ byte: UInt8)

    mutating func write(_ bytes: UnsafeRawBufferPointer)
}
