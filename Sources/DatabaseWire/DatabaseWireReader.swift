import DatabaseTypes

/// Little-endian reader used by database-kit wire DTOs.
@_spi(DatabaseServer)
public struct DatabaseWireReader: Sendable {
    private let bytes: ByteString
    private var offset: Int
    private var nestingDepth: Int
    private var decodedObjectCount: Int
    public let limits: DatabaseWireLimits

    public init(_ bytes: [UInt8], limits: DatabaseWireLimits = .default) {
        self.init(ByteString(bytes), limits: limits)
    }

    public init(
        _ bytes: ByteString,
        limits: DatabaseWireLimits = .default
    ) {
        self.bytes = bytes
        self.offset = 0
        self.nestingDepth = 0
        self.decodedObjectCount = 0
        self.limits = limits
    }

    public var remainingCount: Int {
        bytes.count - offset
    }

    package var registeredObjectCount: Int {
        decodedObjectCount
    }

    package var currentNestingDepth: Int {
        nestingDepth
    }

    var consumedByteCount: Int {
        offset
    }

    mutating func beginSubtreeValidation(
        nestingDepth: Int,
        registeredObjectCount: Int
    ) throws(DatabaseWireError) {
        guard nestingDepth >= 0,
              nestingDepth <= limits.maximumNestingDepth,
              registeredObjectCount >= 0,
              registeredObjectCount <= limits.maximumObjectCount else {
            throw .byteCountOverflow
        }
        self.nestingDepth = nestingDepth
        self.decodedObjectCount = registeredObjectCount
    }

    public mutating func readUInt8() throws(DatabaseWireError) -> UInt8 {
        try validateFrameSize()
        guard offset < bytes.count else {
            throw DatabaseWireError.truncated
        }
        let value = bytes[bytes.startIndex + offset]
        offset += 1
        return value
    }

    public mutating func readBool() throws(DatabaseWireError) -> Bool {
        let rawValue = try readUInt8()
        switch rawValue {
        case 0:
            return false
        case 1:
            return true
        default:
            throw DatabaseWireError.invalidBool(rawValue)
        }
    }

    public mutating func readInt8() throws(DatabaseWireError) -> Int8 {
        Int8(bitPattern: try readUInt8())
    }

    public mutating func readUInt32() throws(DatabaseWireError) -> UInt32 {
        try validateFrameSize()
        guard offset + 4 <= bytes.count else {
            throw DatabaseWireError.truncated
        }
        let value = bytes.withUnsafeBytes { source in
            UInt32(source[offset])
                | (UInt32(source[offset + 1]) << 8)
                | (UInt32(source[offset + 2]) << 16)
                | (UInt32(source[offset + 3]) << 24)
        }
        offset += 4
        return value
    }

    public mutating func readUInt16() throws(DatabaseWireError) -> UInt16 {
        try validateFrameSize()
        guard offset + 2 <= bytes.count else {
            throw DatabaseWireError.truncated
        }
        let value = bytes.withUnsafeBytes { source in
            UInt16(source[offset]) | (UInt16(source[offset + 1]) << 8)
        }
        offset += 2
        return value
    }

    public mutating func readInt16() throws(DatabaseWireError) -> Int16 {
        Int16(bitPattern: try readUInt16())
    }

    public mutating func readInt32() throws(DatabaseWireError) -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    public mutating func readInt64() throws(DatabaseWireError) -> Int64 {
        Int64(bitPattern: try readUInt64())
    }

    public mutating func readInt128() throws(DatabaseWireError) -> Int128 {
        let low = UInt128(try readUInt64())
        let high = UInt128(try readUInt64()) << 64
        return Int128(bitPattern: high | low)
    }

    public mutating func readUInt64() throws(DatabaseWireError) -> UInt64 {
        try validateFrameSize()
        guard offset + 8 <= bytes.count else {
            throw DatabaseWireError.truncated
        }
        let value = bytes.withUnsafeBytes { source in
            UInt64(source[offset])
                | (UInt64(source[offset + 1]) << 8)
                | (UInt64(source[offset + 2]) << 16)
                | (UInt64(source[offset + 3]) << 24)
                | (UInt64(source[offset + 4]) << 32)
                | (UInt64(source[offset + 5]) << 40)
                | (UInt64(source[offset + 6]) << 48)
                | (UInt64(source[offset + 7]) << 56)
        }
        offset += 8
        return value
    }

    public mutating func readDouble() throws(DatabaseWireError) -> Double {
        Double(bitPattern: try readUInt64())
    }

    public mutating func readFloat() throws(DatabaseWireError) -> Float {
        Float(bitPattern: try readUInt32())
    }

    public mutating func readBytes() throws(DatabaseWireError) -> ByteString {
        let intCount = try readLength()
        guard intCount <= limits.maximumByteStringBytes else {
            throw .byteStringTooLarge(actual: intCount, maximum: limits.maximumByteStringBytes)
        }
        guard intCount <= bytes.count - offset else {
            throw DatabaseWireError.truncated
        }
        let lowerBound = bytes.startIndex + offset
        let value = bytes[lowerBound..<(lowerBound + intCount)]
        offset += intCount
        return value
    }

    mutating func readUnframedBytes(
        count: Int
    ) throws(DatabaseWireError) -> ByteString {
        try validateFrameSize()
        guard count >= 0 else {
            throw .byteCountOverflow
        }
        guard count <= bytes.count - offset else {
            throw .truncated
        }
        let lowerBound = bytes.startIndex + offset
        let value = bytes[lowerBound..<(lowerBound + count)]
        offset += count
        return value
    }

    public mutating func readLengthPrefixed<Result>(
        _ decode: (inout DatabaseWireReader) throws(DatabaseWireError) -> Result
    ) throws(DatabaseWireError) -> Result {
        let payload = try readBytes()
        let (childDepth, depthOverflow) = nestingDepth.addingReportingOverflow(1)
        guard !depthOverflow else { throw .byteCountOverflow }
        guard childDepth <= limits.maximumNestingDepth else {
            throw .nestingTooDeep(
                actual: childDepth,
                maximum: limits.maximumNestingDepth
            )
        }
        try registerObjects()

        var child = DatabaseWireReader(payload, limits: limits)
        child.nestingDepth = childDepth
        child.decodedObjectCount = decodedObjectCount
        let result = try decode(&child)
        try child.ensureFullyRead()
        decodedObjectCount = child.decodedObjectCount
        return result
    }

    public mutating func readString() throws(DatabaseWireError) -> String {
        try readString(maximumUTF8Bytes: limits.maximumStringBytes)
    }

    public mutating func readString(
        maximumUTF8Bytes: Int
    ) throws(DatabaseWireError) -> String {
        let encoded = try readValidatedUTF8Bytes(
            maximumUTF8Bytes: maximumUTF8Bytes
        )
        guard let value = DatabaseWireTextDecoder.decode(encoded) else {
            throw DatabaseWireError.invalidUTF8
        }
        return value
    }

    mutating func readValidatedUTF8Bytes(
        maximumUTF8Bytes: Int? = nil
    ) throws(DatabaseWireError) -> ByteString {
        let requestedMaximum = maximumUTF8Bytes ?? limits.maximumStringBytes
        guard requestedMaximum >= 0 else {
            throw .byteCountOverflow
        }
        let count = try readLength()
        let effectiveMaximum = min(
            requestedMaximum,
            limits.maximumStringBytes
        )
        guard count <= effectiveMaximum else {
            throw .stringTooLarge(
                actual: count,
                maximum: effectiveMaximum
            )
        }
        guard count <= bytes.count - offset else {
            throw DatabaseWireError.truncated
        }
        let lowerBound = bytes.startIndex + offset
        let encoded = bytes[lowerBound..<(lowerBound + count)]
        offset += count
        guard DatabaseWireTextDecoder.isValid(encoded) else {
            throw DatabaseWireError.invalidUTF8
        }
        return encoded
    }

    public mutating func readCount() throws(DatabaseWireError) -> Int {
        let count = try readLength()
        guard count <= limits.maximumCollectionCount else {
            throw .collectionTooLarge(actual: count, maximum: limits.maximumCollectionCount)
        }
        try registerObjects(count)
        return count
    }

    public func ensureFullyRead() throws(DatabaseWireError) {
        try validateFrameSize()
        guard remainingCount == 0 else {
            throw DatabaseWireError.trailingBytes
        }
    }

    func bytes(
        inConsumedRange range: Range<Int>
    ) throws(DatabaseWireError) -> ByteString {
        guard range.lowerBound >= 0,
              range.upperBound >= range.lowerBound,
              range.upperBound <= offset,
              range.upperBound <= bytes.count else {
            throw .byteCountOverflow
        }
        let lowerBound = bytes.startIndex + range.lowerBound
        let upperBound = bytes.startIndex + range.upperBound
        return bytes[lowerBound..<upperBound]
    }

    public mutating func withNestedValue<Result>(
        _ body: (inout DatabaseWireReader) throws(DatabaseWireError) -> Result
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
        let (nextDepth, depthOverflow) = nestingDepth.addingReportingOverflow(1)
        guard !depthOverflow else { throw .byteCountOverflow }
        guard nextDepth <= limits.maximumNestingDepth else {
            throw .nestingTooDeep(actual: nextDepth, maximum: limits.maximumNestingDepth)
        }
        try registerObjects(1)
        nestingDepth = nextDepth
    }

    mutating func endNestedValue() throws(DatabaseWireError) {
        guard nestingDepth > 0 else {
            throw .invalidNestingState
        }
        nestingDepth -= 1
    }

    /// Restores reader state while propagating an already selected decode
    /// failure. This cleanup path never converts malformed input into success.
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

    public mutating func registerObjects(_ count: Int = 1) throws(DatabaseWireError) {
        guard count >= 0, decodedObjectCount <= Int.max - count else {
            throw .byteCountOverflow
        }
        decodedObjectCount += count
        guard decodedObjectCount <= limits.maximumObjectCount else {
            throw .objectBudgetExceeded(
                actual: decodedObjectCount,
                maximum: limits.maximumObjectCount
            )
        }
    }

    private mutating func readLength() throws(DatabaseWireError) -> Int {
        let count = try readUInt32()
        guard UInt64(count) <= UInt64(Int.max) else {
            throw DatabaseWireError.byteCountOverflow
        }
        return Int(count)
    }

    private func validateFrameSize() throws(DatabaseWireError) {
        guard bytes.count <= limits.maximumFrameBytes else {
            throw .frameTooLarge(actual: bytes.count, maximum: limits.maximumFrameBytes)
        }
    }
}
