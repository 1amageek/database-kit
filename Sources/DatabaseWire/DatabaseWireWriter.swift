import DatabaseKit
import DatabaseTypes

/// Little-endian writer used by database-kit wire DTOs.
///
/// Exact-size encoding writes directly into the final `ByteString` storage.
/// The mutable pointer is confined to the synchronous `encode` call and never
/// crosses a concurrency boundary.
struct DatabaseWireWriter {
    private enum Destination {
        case measuring
        case fixed(UnsafeMutableRawBufferPointer)
        case borrowed((UnsafeRawBufferPointer) -> Void)
    }

    public let limits: DatabaseWireLimits
    private var destination: Destination
    private var measuredByteCount: Int
    private var outputOffset: Int
    private var nestingDepth: Int
    private var encodedObjectCount: Int
    private var deferredError: DatabaseWireError?

    init(measuring limits: DatabaseWireLimits) {
        self.destination = .measuring
        self.limits = limits
        self.measuredByteCount = 0
        self.outputOffset = 0
        self.nestingDepth = 0
        self.encodedObjectCount = 0
        self.deferredError = nil
    }

    private init(
        fixedOutput: UnsafeMutableRawBufferPointer,
        limits: DatabaseWireLimits
    ) {
        self.destination = .fixed(fixedOutput)
        self.limits = limits
        self.measuredByteCount = 0
        self.outputOffset = 0
        self.nestingDepth = 0
        self.encodedObjectCount = 0
        self.deferredError = nil
    }

    private init(
        borrowedSink: @escaping (UnsafeRawBufferPointer) -> Void,
        limits: DatabaseWireLimits
    ) {
        self.destination = .borrowed(borrowedSink)
        self.limits = limits
        self.measuredByteCount = 0
        self.outputOffset = 0
        self.nestingDepth = 0
        self.encodedObjectCount = 0
        self.deferredError = nil
    }

    private var writtenByteCount: Int {
        if case .measuring = destination {
            return measuredByteCount
        }
        return outputOffset
    }

    private var isMeasuring: Bool {
        if case .measuring = destination {
            return true
        }
        return false
    }

    var registeredObjectCount: Int {
        encodedObjectCount
    }

    var currentNestingDepth: Int {
        nestingDepth
    }

    /// Returns the canonical encoded byte count after applying all writer and
    /// frame limits, without allocating output storage.
    ///
    /// The encoding closure runs exactly once. Writer byte-payload operations
    /// use declared lengths and do not borrow their owners while counting.
    public static func encodedByteCount(
        limits: DatabaseWireLimits = .default,
        _ encode: (inout DatabaseWireWriter) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireError) -> Int {
        var writer = DatabaseWireWriter(measuring: limits)
        try encode(&writer)
        try writer.ensureNoDeferredError()
        let byteCount = writer.writtenByteCount
        guard byteCount <= limits.maximumFrameBytes else {
            throw .frameTooLarge(
                actual: byteCount,
                maximum: limits.maximumFrameBytes
            )
        }
        return byteCount
    }

    public static func encode(
        limits: DatabaseWireLimits = .default,
        _ encode: (inout DatabaseWireWriter) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireError) -> ByteString {
        let byteCount = try Self.encodedByteCount(
            limits: limits,
            encode
        )

        return try ByteString.copying(count: byteCount) {
            (output: UnsafeMutableRawBufferPointer) throws(DatabaseWireError) -> Void in
            var writer = DatabaseWireWriter(
                fixedOutput: output,
                limits: limits
            )
            try encode(&writer)
            try writer.ensureNoDeferredError()
            guard writer.writtenByteCount == byteCount else {
                throw .byteCountOverflow
            }
        }
    }

    /// Measures first, calls `prepare` before any output, and then lends each
    /// encoded span directly to a synchronous consumer.
    ///
    /// The buffer passed to `consume` is valid only until that call returns.
    /// The consumer must not retain the pointer. This internal primitive is
    /// intentionally limited to canonical codecs that never back-patch output.
    public static func emit<DestinationFailure: Error>(
        limits: DatabaseWireLimits,
        prepare: (Int) throws(DestinationFailure) -> Void,
        consume: (UnsafeRawBufferPointer) -> Void,
        _ encode: (
            inout DatabaseWireWriter
        ) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireEmissionError<DestinationFailure>) {
        let byteCount: Int
        do {
            byteCount = try Self.encodedByteCount(
                limits: limits,
                encode
            )
        } catch {
            throw .encoding(error)
        }

        do {
            try prepare(byteCount)
        } catch {
            throw .destination(error)
        }

        let result: Result<Void, DatabaseWireError> = withoutActuallyEscaping(
            consume
        ) { escapingConsume in
            Self.result {
                () throws(DatabaseWireError) -> Void in
                var writer = DatabaseWireWriter(
                    borrowedSink: escapingConsume,
                    limits: limits
                )
                try encode(&writer)
                try writer.ensureNoDeferredError()
                guard writer.writtenByteCount == byteCount else {
                    throw DatabaseWireError.byteCountOverflow
                }
            }
        }
        if case .failure(let error) = result {
            throw .encoding(error)
        }
    }

    /// Measures first, reports the exact byte count, and then lends each
    /// encoded span directly to a synchronous consumer.
    ///
    /// `willEmit` completes before `consume` is called. Buffers passed to
    /// `consume` are valid only until that call returns.
    public static func emit(
        limits: DatabaseWireLimits = .default,
        willEmit: (Int) -> Void,
        consume: (UnsafeRawBufferPointer) -> Void,
        _ encode: (
            inout DatabaseWireWriter
        ) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireError) {
        let byteCount = try Self.encodedByteCount(
            limits: limits,
            encode
        )
        willEmit(byteCount)

        let result: Result<Void, DatabaseWireError> = withoutActuallyEscaping(
            consume
        ) { escapingConsume in
            Self.result {
                () throws(DatabaseWireError) -> Void in
                var writer = DatabaseWireWriter(
                    borrowedSink: escapingConsume,
                    limits: limits
                )
                try encode(&writer)
                try writer.ensureNoDeferredError()
                guard writer.writtenByteCount == byteCount else {
                    throw DatabaseWireError.byteCountOverflow
                }
            }
        }
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    /// Lends each canonical encoded span directly to a synchronous consumer.
    ///
    /// This overload performs no output allocation. The consumer must not
    /// retain the borrowed pointer beyond the call.
    public static func emit(
        limits: DatabaseWireLimits = .default,
        consume: (UnsafeRawBufferPointer) -> Void,
        _ encode: (
            inout DatabaseWireWriter
        ) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireError) {
        try Self.emit(
            limits: limits,
            willEmit: { _ in },
            consume: consume,
            encode
        )
    }

    private static func result<Success, Failure: Error>(
        of operation: () throws(Failure) -> Success
    ) -> Result<Success, Failure> {
        do {
            return .success(try operation())
        } catch {
            return .failure(error)
        }
    }

    public mutating func writeUInt8(_ value: UInt8) {
        if isMeasuring {
            recordMeasuredBytes(1)
        } else {
            appendByte(value)
        }
    }

    public mutating func writeBool(_ value: Bool) {
        writeUInt8(value ? 1 : 0)
    }

    public mutating func writeInt8(_ value: Int8) {
        writeUInt8(UInt8(bitPattern: value))
    }

    public mutating func writeUInt32(_ value: UInt32) {
        if isMeasuring {
            recordMeasuredBytes(4)
            return
        }
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { source in
            appendBytes(source)
        }
    }

    public mutating func writeUInt16(_ value: UInt16) {
        if isMeasuring {
            recordMeasuredBytes(2)
            return
        }
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { source in
            appendBytes(source)
        }
    }

    public mutating func writeInt16(_ value: Int16) {
        writeUInt16(UInt16(bitPattern: value))
    }

    public mutating func writeInt32(_ value: Int32) {
        writeUInt32(UInt32(bitPattern: value))
    }

    public mutating func writeInt64(_ value: Int64) {
        writeUInt64(UInt64(bitPattern: value))
    }

    public mutating func writeInt128(_ value: Int128) {
        writeUInt64(UInt64(truncatingIfNeeded: value))
        writeUInt64(UInt64(truncatingIfNeeded: value >> 64))
    }

    public mutating func writeUInt64(_ value: UInt64) {
        if isMeasuring {
            recordMeasuredBytes(8)
            return
        }
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { source in
            appendBytes(source)
        }
    }

    public mutating func writeDouble(_ value: Double) {
        writeUInt64(value.bitPattern)
    }

    public mutating func writeFloat(_ value: Float) {
        writeUInt32(value.bitPattern)
    }

    public mutating func writeBytes(_ value: [UInt8]) throws(DatabaseWireError) {
        try writeBytes(ByteString(value))
    }

    public mutating func writeBytes(
        _ value: ByteString
    ) throws(DatabaseWireError) {
        guard value.count <= limits.maximumByteStringBytes else {
            throw .byteStringTooLarge(actual: value.count, maximum: limits.maximumByteStringBytes)
        }
        try writeLength(value.count)
        if isMeasuring {
            recordMeasuredBytes(value.count)
        } else {
            value.withUnsafeBytes { source in
                appendBytes(source)
            }
        }
    }

    public mutating func writeString(_ value: String) throws(DatabaseWireError) {
        let encodedCount = value.utf8.count
        guard encodedCount <= limits.maximumStringBytes else {
            throw .stringTooLarge(actual: encodedCount, maximum: limits.maximumStringBytes)
        }
        try writeLength(encodedCount)
        if isMeasuring {
            recordMeasuredBytes(encodedCount)
        } else {
            let emittedContiguousStorage = value.utf8.withContiguousStorageIfAvailable {
                source -> Bool in
                appendBytes(UnsafeRawBufferPointer(source))
                return true
            } ?? false
            if !emittedContiguousStorage {
                // A String may expose noncontiguous UTF-8. The scalar fallback
                // avoids materializing an intermediate byte array.
                for byte in value.utf8 {
                    appendByte(byte)
                }
            }
        }
    }

    public mutating func writeCount(_ count: Int) throws(DatabaseWireError) {
        guard count <= limits.maximumCollectionCount else {
            throw .collectionTooLarge(actual: count, maximum: limits.maximumCollectionCount)
        }
        try registerObjects(count)
        try writeLength(count)
    }

    public mutating func withNestedValue<Result>(
        _ body: (inout DatabaseWireWriter) throws(DatabaseWireError) -> Result
    ) throws(DatabaseWireError) -> Result {
        let enclosingDepth = nestingDepth
        try beginNestedValue()
        do {
            let result = try body(&self)
            try endNestedValue()
            return result
        } catch let error {
            nestingDepth = enclosingDepth
            throw error
        }
    }

    mutating func beginNestedValue() throws(DatabaseWireError) {
        let (nextDepth, depthOverflow) = nestingDepth
            .addingReportingOverflow(1)
        guard !depthOverflow else { throw .byteCountOverflow }
        guard nextDepth <= limits.maximumNestingDepth else {
            throw .nestingTooDeep(
                actual: nextDepth,
                maximum: limits.maximumNestingDepth
            )
        }
        try registerObjects()
        nestingDepth = nextDepth
    }

    mutating func endNestedValue() throws(DatabaseWireError) {
        guard nestingDepth > 0 else {
            throw .invalidNestingState
        }
        nestingDepth -= 1
    }

    /// Restores writer state while propagating an already selected encode
    /// failure. This cleanup path never converts invalid output into success.
    mutating func abandonNestedValues(_ count: Int) {
        guard count > 0 else {
            return
        }
        if count >= nestingDepth {
            nestingDepth = 0
        } else {
            nestingDepth -= count
        }
    }

    public mutating func registerObjects(
        _ count: Int = 1
    ) throws(DatabaseWireError) {
        guard count >= 0,
              encodedObjectCount <= Int.max - count else {
            throw .byteCountOverflow
        }
        encodedObjectCount += count
        guard encodedObjectCount <= limits.maximumObjectCount else {
            throw .objectBudgetExceeded(
                actual: encodedObjectCount,
                maximum: limits.maximumObjectCount
            )
        }
    }

    private mutating func writeLength(_ count: Int) throws(DatabaseWireError) {
        guard count >= 0, UInt64(count) <= UInt64(UInt32.max) else {
            throw DatabaseWireError.byteCountOverflow
        }
        writeUInt32(UInt32(count))
    }

    public mutating func writeLengthPrefixed(
        _ encode: (inout DatabaseWireWriter) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireError) {
        if case .borrowed = destination {
            // Streaming output cannot be back-patched. Canonical streaming
            // codecs must write known lengths before emitting their payload.
            throw .invalidQueryIRWireState
        }
        try writeBackpatchedLengthPrefixed(encode)
    }

    private mutating func writeBackpatchedLengthPrefixed(
        _ encode: (inout DatabaseWireWriter) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireError) {
        let lengthOffset = writtenByteCount
        writeUInt32(0)
        let payloadOffset = writtenByteCount
        try withNestedValue {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try encode(&writer)
        }
        let payloadCount = writtenByteCount - payloadOffset
        guard payloadCount <= limits.maximumByteStringBytes else {
            throw .byteStringTooLarge(
                actual: payloadCount,
                maximum: limits.maximumByteStringBytes
            )
        }
        guard UInt64(payloadCount) <= UInt64(UInt32.max) else {
            throw .byteCountOverflow
        }
        guard !isMeasuring else {
            return
        }
        replaceUInt32(UInt32(payloadCount), at: lengthOffset)
    }

    mutating func writeUnframedBytes(_ value: ByteString) {
        if isMeasuring {
            recordMeasuredBytes(value.count)
        } else {
            value.withUnsafeBytes { source in
                appendBytes(source)
            }
        }
    }

    mutating func writeCanonicalRDFTerm(
        _ term: RDFTerm,
        role: RDFTermRole = .term
    ) throws(DatabaseWireError) {
        guard limits.maximumObjectCount > encodedObjectCount else {
            let (actual, overflow) = encodedObjectCount.addingReportingOverflow(1)
            throw .objectBudgetExceeded(
                actual: overflow ? Int.max : actual,
                maximum: limits.maximumObjectCount
            )
        }
        let remainingObjectCount = limits.maximumObjectCount
            - encodedObjectCount
        guard limits.maximumNestingDepth >= nestingDepth else {
            throw .nestingTooDeep(
                actual: nestingDepth,
                maximum: limits.maximumNestingDepth
            )
        }
        let remainingDepth = limits.maximumNestingDepth - nestingDepth
        let codecLimits = RDFTermCodecLimits(
            validatedMaximumBytes: limits.maximumByteStringBytes,
            maximumDepth: remainingDepth,
            maximumObjectCount: remainingObjectCount
        )
        let plan: RDFTermEncodingPlan
        do {
            plan = try RDFTermCodec.encodingPlan(
                term,
                role: role,
                limits: codecLimits
            )
        } catch let error {
            throw mapCanonicalRDFTermError(error)
        }
        try registerObjects(plan.objectCount)

        try writeLength(plan.byteCount)
        if isMeasuring {
            recordMeasuredBytes(plan.byteCount)
            return
        }

        do {
            try RDFTermCodec.encode(plan, into: &self)
        } catch let error {
            throw mapCanonicalRDFTermError(error)
        }
    }

    private func mapCanonicalRDFTermError(
        _ error: RDFTermCodecError
    ) -> DatabaseWireError {
        switch error {
        case .maximumBytesExceeded(let actual, _):
            return .byteStringTooLarge(
                actual: actual,
                maximum: limits.maximumByteStringBytes
            )
        case .maximumDepthExceeded(let actual, _):
            let (combined, overflow) = nestingDepth.addingReportingOverflow(actual)
            guard !overflow else { return .byteCountOverflow }
            return .nestingTooDeep(
                actual: combined,
                maximum: limits.maximumNestingDepth
            )
        case .maximumObjectCountExceeded(let actual, _):
            let (combined, overflow) = encodedObjectCount.addingReportingOverflow(actual)
            guard !overflow else { return .byteCountOverflow }
            return .objectBudgetExceeded(
                actual: combined,
                maximum: limits.maximumObjectCount
            )
        default:
            return .invalidCanonicalRDFTerm(error)
        }
    }

    private mutating func appendByte(_ value: UInt8) {
        var byte = value
        Swift.withUnsafeBytes(of: &byte) { source in
            appendBytes(source)
        }
    }

    private mutating func appendBytes(_ source: UnsafeRawBufferPointer) {
        guard !source.isEmpty else { return }
        guard deferredError == nil else { return }
        let (nextOffset, overflow) = outputOffset.addingReportingOverflow(source.count)
        guard !overflow else {
            deferredError = .byteCountOverflow
            return
        }
        switch destination {
        case .fixed(let output):
            guard outputOffset <= output.count,
                  source.count <= output.count - outputOffset else {
                deferredError = .byteCountOverflow
                return
            }
            let destination = UnsafeMutableRawBufferPointer(
                rebasing: output[outputOffset..<nextOffset]
            )
            destination.copyMemory(from: source)
            outputOffset = nextOffset
        case .borrowed(let borrowedSink):
            borrowedSink(source)
            outputOffset = nextOffset
        case .measuring:
            recordMeasuredBytes(source.count)
        }
    }

    private mutating func replaceUInt32(_ value: UInt32, at offset: Int) {
        guard offset >= 0,
              offset <= writtenByteCount,
              writtenByteCount - offset >= 4 else {
            deferredError = .byteCountOverflow
            return
        }
        guard case .fixed(let output) = destination else {
            deferredError = .invalidQueryIRWireState
            return
        }
        output[offset] = UInt8(truncatingIfNeeded: value)
        output[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        output[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        output[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    private mutating func recordMeasuredBytes(_ count: Int) {
        guard deferredError == nil else { return }
        guard count >= 0 else {
            deferredError = .byteCountOverflow
            return
        }
        let (next, overflow) = measuredByteCount.addingReportingOverflow(count)
        guard !overflow else {
            deferredError = .byteCountOverflow
            return
        }
        measuredByteCount = next
    }

    private func ensureNoDeferredError() throws(DatabaseWireError) {
        if let deferredError {
            throw deferredError
        }
    }
}

extension DatabaseWireWriter: RDFTermEncodingSink {
    public mutating func write(_ byte: UInt8) {
        appendByte(byte)
    }

    public mutating func write(_ bytes: UnsafeRawBufferPointer) {
        appendBytes(bytes)
    }
}
