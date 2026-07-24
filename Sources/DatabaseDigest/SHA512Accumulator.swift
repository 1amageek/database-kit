public import DatabaseTypes

/// Incrementally computes a canonical SHA-512 digest.
///
/// Input buffers are borrowed synchronously. Finalization allocates only the
/// 64-byte digest result and consumes the accumulator.
public struct SHA512Accumulator: Sendable {
    public static let digestByteCount = 64

    private var state = SHA512FamilyAccumulator(variant: .sha512)

    public init() {}

    public mutating func update(_ bytes: ByteString) {
        state.update(bytes)
    }

    public mutating func update(_ byte: UInt8) {
        state.update(byte)
    }

    /// Borrows `source` only for the duration of this call.
    public mutating func update(_ source: UnsafeRawBufferPointer) {
        state.update(source)
    }

    public mutating func update(utf8 value: String) {
        state.update(utf8: value)
    }

    public consuming func finalize() -> ByteString {
        state.finalize(digestByteCount: Self.digestByteCount)
    }

    /// Lends the finalized digest for exactly one synchronous callback.
    ///
    /// The pointer must not escape `body`.
    public consuming func withUnsafeDigestBytes<Result, Failure: Error>(
        _ body: (UnsafeRawBufferPointer) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try state.withUnsafeDigestBytes(
            digestByteCount: Self.digestByteCount,
            body
        )
    }
}
