import DatabaseValue

/// Little-endian writer used by database-kit wire DTOs.
///
/// Exact-size encoding writes directly into the final `DatabaseBytes` storage.
/// The mutable pointer is confined to the synchronous `encode` call and never
/// crosses a concurrency boundary.
public struct DatabaseWireWriter {
    public let limits: DatabaseWireLimits
    private var arrayBytes: [UInt8]?
    private var fixedOutput: UnsafeMutableRawBufferPointer?
    private var borrowedSink: ((UnsafeRawBufferPointer) -> Void)?
    private let isMeasuring: Bool
    private var measuredByteCount: Int
    private var outputOffset: Int
    private var nestingDepth: Int
    private var encodedObjectCount: Int
    private var deferredError: DatabaseWireError?

    public var bytes: [UInt8] {
        guard let arrayBytes else {
            preconditionFailure(
                "Exact-size and measuring writers do not expose mutable array storage"
            )
        }
        return arrayBytes
    }

    public init(limits: DatabaseWireLimits = .default) {
        self.arrayBytes = []
        self.fixedOutput = nil
        self.borrowedSink = nil
        self.limits = limits
        self.isMeasuring = false
        self.measuredByteCount = 0
        self.outputOffset = 0
        self.nestingDepth = 0
        self.encodedObjectCount = 0
        self.deferredError = nil
    }

    public init(capacity: Int, limits: DatabaseWireLimits = .default) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(capacity)
        self.arrayBytes = bytes
        self.fixedOutput = nil
        self.borrowedSink = nil
        self.limits = limits
        self.isMeasuring = false
        self.measuredByteCount = 0
        self.outputOffset = 0
        self.nestingDepth = 0
        self.encodedObjectCount = 0
        self.deferredError = nil
    }

    init(measuring limits: DatabaseWireLimits) {
        self.arrayBytes = nil
        self.fixedOutput = nil
        self.borrowedSink = nil
        self.limits = limits
        self.isMeasuring = true
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
        self.arrayBytes = nil
        self.fixedOutput = fixedOutput
        self.borrowedSink = nil
        self.limits = limits
        self.isMeasuring = false
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
        self.arrayBytes = nil
        self.fixedOutput = nil
        self.borrowedSink = borrowedSink
        self.limits = limits
        self.isMeasuring = false
        self.measuredByteCount = 0
        self.outputOffset = 0
        self.nestingDepth = 0
        self.encodedObjectCount = 0
        self.deferredError = nil
    }

    public var writtenByteCount: Int {
        if isMeasuring {
            return measuredByteCount
        }
        if fixedOutput != nil || borrowedSink != nil {
            return outputOffset
        }
        guard let arrayBytes else {
            preconditionFailure("Database wire writer has no output storage")
        }
        return arrayBytes.count
    }

    public static func encode(
        limits: DatabaseWireLimits = .default,
        _ encode: (inout DatabaseWireWriter) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireError) -> DatabaseBytes {
        var measuringWriter = DatabaseWireWriter(measuring: limits)
        try encode(&measuringWriter)
        try measuringWriter.ensureNoDeferredError()
        let byteCount = measuringWriter.writtenByteCount
        guard byteCount <= limits.maximumFrameBytes else {
            throw .frameTooLarge(
                actual: byteCount,
                maximum: limits.maximumFrameBytes
            )
        }

        return try DatabaseBytes.copying(count: byteCount) {
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

    /// Performs exact-size two-pass encoding for codecs with domain-specific errors.
    public static func encodeThrowing(
        limits: DatabaseWireLimits = .default,
        _ encode: (inout DatabaseWireWriter) throws -> Void
    ) throws -> DatabaseBytes {
        var measuringWriter = DatabaseWireWriter(measuring: limits)
        try encode(&measuringWriter)
        try measuringWriter.ensureNoDeferredError()
        let byteCount = measuringWriter.writtenByteCount
        guard byteCount <= limits.maximumFrameBytes else {
            throw DatabaseWireError.frameTooLarge(
                actual: byteCount,
                maximum: limits.maximumFrameBytes
            )
        }

        return try DatabaseBytes.copying(count: byteCount) { output in
            var writer = DatabaseWireWriter(
                fixedOutput: output,
                limits: limits
            )
            try encode(&writer)
            try writer.ensureNoDeferredError()
            guard writer.writtenByteCount == byteCount else {
                throw DatabaseWireError.byteCountOverflow
            }
        }
    }

    /// Measures first, calls `prepare` before any output, and then lends each
    /// encoded span directly to a synchronous consumer.
    ///
    /// The buffer passed to `consume` is valid only until that call returns.
    /// The consumer must not retain the pointer. This internal primitive is
    /// intentionally limited to canonical codecs that never back-patch output.
    public static func emit(
        limits: DatabaseWireLimits,
        prepare: (Int) throws -> Void,
        consume: (UnsafeRawBufferPointer) -> Void,
        _ encode: (
            inout DatabaseWireWriter
        ) throws(DatabaseWireError) -> Void
    ) throws {
        var measuringWriter = DatabaseWireWriter(measuring: limits)
        try encode(&measuringWriter)
        try measuringWriter.ensureNoDeferredError()
        let byteCount = measuringWriter.writtenByteCount
        guard byteCount <= limits.maximumFrameBytes else {
            throw DatabaseWireError.frameTooLarge(
                actual: byteCount,
                maximum: limits.maximumFrameBytes
            )
        }

        try prepare(byteCount)

        try withoutActuallyEscaping(consume) { escapingConsume in
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

    public mutating func writeInt32(_ value: Int32) {
        writeUInt32(UInt32(bitPattern: value))
    }

    public mutating func writeInt64(_ value: Int64) {
        writeUInt64(UInt64(bitPattern: value))
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

    public mutating func writeBytes(_ value: [UInt8]) throws(DatabaseWireError) {
        try writeBytes(DatabaseBytes(value))
    }

    public mutating func writeBytes(
        _ value: DatabaseBytes
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
        try beginNestedValue()
        defer { endNestedValue() }
        return try body(&self)
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

    mutating func endNestedValue() {
        precondition(nestingDepth > 0, "Unbalanced database wire nesting")
        nestingDepth -= 1
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
        guard borrowedSink == nil else {
            // Streaming output cannot be back-patched. Canonical streaming
            // codecs must write known lengths before emitting their payload.
            throw .invalidQueryIRWireState
        }
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

    mutating func writeUnframedBytes(_ value: DatabaseBytes) {
        if isMeasuring {
            recordMeasuredBytes(value.count)
        } else {
            value.withUnsafeBytes { source in
                appendBytes(source)
            }
        }
    }

    mutating func writeCanonicalRDFTerm(
        _ term: DatabaseRDFTerm,
        role: DatabaseRDFTermRole = .term
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
        let codecLimits = DatabaseRDFTermCodecLimits(
            maximumBytes: limits.maximumByteStringBytes,
            maximumDepth: remainingDepth,
            maximumObjectCount: remainingObjectCount
        )
        let plan: DatabaseRDFTermEncodingPlan
        do {
            plan = try DatabaseRDFTermCodec.encodingPlan(
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
            try DatabaseRDFTermCodec.encode(plan, into: &self)
        } catch let error {
            throw mapCanonicalRDFTermError(error)
        }
    }

    private func mapCanonicalRDFTermError(
        _ error: DatabaseRDFTermCodecError
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
        if let output = fixedOutput {
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
            return
        }
        if let borrowedSink {
            borrowedSink(source)
            outputOffset = nextOffset
            return
        }
        guard arrayBytes != nil else {
            preconditionFailure("Database wire writer has no output storage")
        }
        arrayBytes!.append(contentsOf: source)
        outputOffset = nextOffset
    }

    private mutating func replaceUInt32(_ value: UInt32, at offset: Int) {
        precondition(offset >= 0 && offset + 4 <= writtenByteCount)
        if let output = fixedOutput {
            output[offset] = UInt8(truncatingIfNeeded: value)
            output[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
            output[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
            output[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
            return
        }
        guard arrayBytes != nil else {
            preconditionFailure("Database wire writer has no output storage")
        }
        arrayBytes![offset] = UInt8(truncatingIfNeeded: value)
        arrayBytes![offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        arrayBytes![offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        arrayBytes![offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
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

extension DatabaseWireWriter: DatabaseRDFTermEncodingSink {
    public mutating func write(_ byte: UInt8) {
        appendByte(byte)
    }

    public mutating func write(_ bytes: UnsafeRawBufferPointer) {
        appendBytes(bytes)
    }
}
