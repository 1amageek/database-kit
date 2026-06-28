/// Little-endian writer used by database-kit wire DTOs.
public struct DatabaseWireBinaryWriter: Sendable {
    public private(set) var bytes: [UInt8]

    public init() {
        self.bytes = []
    }

    public init(capacity: Int) {
        self.bytes = []
        self.bytes.reserveCapacity(capacity)
    }

    public mutating func writeUInt8(_ value: UInt8) {
        bytes.append(value)
    }

    public mutating func writeBool(_ value: Bool) {
        writeUInt8(value ? 1 : 0)
    }

    public mutating func writeUInt32(_ value: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    public mutating func writeInt64(_ value: Int64) {
        writeUInt64(UInt64(bitPattern: value))
    }

    public mutating func writeUInt64(_ value: UInt64) {
        let unsigned = value
        bytes.append(UInt8(truncatingIfNeeded: unsigned))
        bytes.append(UInt8(truncatingIfNeeded: unsigned >> 8))
        bytes.append(UInt8(truncatingIfNeeded: unsigned >> 16))
        bytes.append(UInt8(truncatingIfNeeded: unsigned >> 24))
        bytes.append(UInt8(truncatingIfNeeded: unsigned >> 32))
        bytes.append(UInt8(truncatingIfNeeded: unsigned >> 40))
        bytes.append(UInt8(truncatingIfNeeded: unsigned >> 48))
        bytes.append(UInt8(truncatingIfNeeded: unsigned >> 56))
    }

    public mutating func writeDouble(_ value: Double) {
        writeUInt64(value.bitPattern)
    }

    public mutating func writeBytes(_ value: [UInt8]) throws(DatabaseWireError) {
        try writeCount(value.count)
        bytes.append(contentsOf: value)
    }

    public mutating func writeString(_ value: String) throws(DatabaseWireError) {
        try writeBytes(Array(value.utf8))
    }

    public mutating func writeCount(_ count: Int) throws(DatabaseWireError) {
        guard count >= 0, UInt64(count) <= UInt64(UInt32.max) else {
            throw DatabaseWireError.byteCountOverflow
        }
        writeUInt32(UInt32(count))
    }
}
