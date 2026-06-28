/// Little-endian reader used by database-kit wire DTOs.
public struct DatabaseWireBinaryReader: Sendable {
    private let bytes: [UInt8]
    private var offset: Int

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
        self.offset = 0
    }

    public var remainingCount: Int {
        bytes.count - offset
    }

    public mutating func readUInt8() throws(DatabaseWireError) -> UInt8 {
        guard offset < bytes.count else {
            throw DatabaseWireError.truncated
        }
        let value = bytes[offset]
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

    public mutating func readUInt32() throws(DatabaseWireError) -> UInt32 {
        guard offset + 4 <= bytes.count else {
            throw DatabaseWireError.truncated
        }
        let value = UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
        offset += 4
        return value
    }

    public mutating func readInt64() throws(DatabaseWireError) -> Int64 {
        Int64(bitPattern: try readUInt64())
    }

    public mutating func readUInt64() throws(DatabaseWireError) -> UInt64 {
        guard offset + 8 <= bytes.count else {
            throw DatabaseWireError.truncated
        }
        let value = UInt64(bytes[offset])
            | (UInt64(bytes[offset + 1]) << 8)
            | (UInt64(bytes[offset + 2]) << 16)
            | (UInt64(bytes[offset + 3]) << 24)
            | (UInt64(bytes[offset + 4]) << 32)
            | (UInt64(bytes[offset + 5]) << 40)
            | (UInt64(bytes[offset + 6]) << 48)
            | (UInt64(bytes[offset + 7]) << 56)
        offset += 8
        return value
    }

    public mutating func readDouble() throws(DatabaseWireError) -> Double {
        Double(bitPattern: try readUInt64())
    }

    public mutating func readBytes() throws(DatabaseWireError) -> [UInt8] {
        let intCount = try readCount()
        guard offset + intCount <= bytes.count else {
            throw DatabaseWireError.truncated
        }
        let value = Array(bytes[offset..<(offset + intCount)])
        offset += intCount
        return value
    }

    public mutating func readString() throws(DatabaseWireError) -> String {
        let bytes = try readBytes()
        guard let value = String(validating: bytes, as: UTF8.self) else {
            throw DatabaseWireError.invalidUTF8
        }
        return value
    }

    public mutating func readCount() throws(DatabaseWireError) -> Int {
        let count = try readUInt32()
        guard UInt64(count) <= UInt64(Int.max) else {
            throw DatabaseWireError.byteCountOverflow
        }
        return Int(count)
    }

    public func ensureFullyRead() throws(DatabaseWireError) {
        guard remainingCount == 0 else {
            throw DatabaseWireError.trailingBytes
        }
    }
}
