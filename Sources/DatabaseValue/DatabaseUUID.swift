public struct DatabaseUUID:
    Sendable,
    Hashable,
    Comparable,
    CustomStringConvertible,
    RandomAccessCollection {
    public typealias Element = UInt8
    public typealias Index = Int

    public let high: UInt64
    public let low: UInt64

    public init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    public init?<Bytes: Collection>(bytes: Bytes) where Bytes.Element == UInt8 {
        guard bytes.count == 16 else { return nil }

        var high: UInt64 = 0
        var low: UInt64 = 0
        for (offset, byte) in bytes.enumerated() {
            if offset < 8 {
                high = (high << 8) | UInt64(byte)
            } else {
                low = (low << 8) | UInt64(byte)
            }
        }
        self.init(high: high, low: low)
    }

    public init?(canonicalString: String) {
        var iterator = canonicalString.utf8.makeIterator()
        var high: UInt64 = 0
        var low: UInt64 = 0

        for byteOffset in 0..<16 {
            if byteOffset == 4 || byteOffset == 6 || byteOffset == 8 || byteOffset == 10 {
                guard iterator.next() == 45 else {
                    return nil
                }
            }

            guard let highCharacter = iterator.next(),
                  let lowCharacter = iterator.next(),
                  let highNibble = Self.hexadecimalValue(highCharacter),
                  let lowNibble = Self.hexadecimalValue(lowCharacter) else {
                return nil
            }
            let byte = (highNibble << 4) | lowNibble
            if byteOffset < 8 {
                high = (high << 8) | UInt64(byte)
            } else {
                low = (low << 8) | UInt64(byte)
            }
        }
        guard iterator.next() == nil else {
            return nil
        }
        self.init(high: high, low: low)
    }

    public var bytes: [UInt8] {
        Array(self)
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { 16 }

    public subscript(position: Int) -> UInt8 {
        precondition(indices.contains(position))
        let source = position < 8 ? high : low
        let shift = UInt64((7 - (position & 7)) * 8)
        return UInt8(truncatingIfNeeded: source >> shift)
    }

    public var description: String {
        String(unsafeUninitializedCapacity: 36) { encoded in
            var encodedOffset = 0
            for byteOffset in 0..<16 {
                if byteOffset == 4 || byteOffset == 6 || byteOffset == 8 || byteOffset == 10 {
                    encoded[encodedOffset] = 45
                    encodedOffset += 1
                }
                let shift = UInt64((7 - (byteOffset & 7)) * 8)
                let source = byteOffset < 8 ? high : low
                let byte = UInt8(truncatingIfNeeded: source >> shift)
                encoded[encodedOffset] = Self.hexadecimalCharacter(byte >> 4)
                encoded[encodedOffset + 1] = Self.hexadecimalCharacter(byte & 0x0F)
                encodedOffset += 2
            }
            return encodedOffset
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.high != rhs.high { return lhs.high < rhs.high }
        return lhs.low < rhs.low
    }

    private static func hexadecimalValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    private static func hexadecimalCharacter(_ value: UInt8) -> UInt8 {
        value < 10 ? 48 + value : 87 + value
    }
}
