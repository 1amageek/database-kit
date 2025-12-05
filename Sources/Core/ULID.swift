import struct Foundation.Date

/// ULID (Universally Unique Lexicographically Sortable Identifier)
///
/// A 128-bit identifier that is:
/// - Lexicographically sortable
/// - Time-ordered (first 48 bits are timestamp)
/// - Randomly generated (last 80 bits are random)
/// - Case-insensitive and URL-safe
///
/// **Format**: `TTTTTTTTTTRRRRRRRRRRRRRRRRR` (26 characters, Crockford's Base32)
/// - `T`: Timestamp (10 chars, 48 bits, milliseconds since Unix epoch)
/// - `R`: Randomness (16 chars, 80 bits)
///
/// **Usage**:
/// ```swift
/// let ulid = ULID()
/// print(ulid.ulidString)  // "01HXK5M3N2P4Q5R6S7T8U9V0WX"
/// ```
///
/// **Reference**: https://github.com/ulid/spec
public struct ULID: Sendable, Hashable, Codable, CustomStringConvertible {

    /// The raw 128-bit value (16 bytes)
    public let rawValue: (UInt64, UInt64)

    /// Crockford's Base32 encoding alphabet
    private static let encodingChars: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Decoding map for Crockford's Base32
    private static let decodingMap: [Character: UInt8] = {
        var map: [Character: UInt8] = [:]
        for (index, char) in encodingChars.enumerated() {
            map[char] = UInt8(index)
            map[Character(char.lowercased())] = UInt8(index)
        }
        // Handle commonly confused characters
        map["I"] = 1  // I -> 1
        map["i"] = 1
        map["L"] = 1  // L -> 1
        map["l"] = 1
        map["O"] = 0  // O -> 0
        map["o"] = 0
        return map
    }()

    /// Creates a new ULID with current timestamp and random data
    public init() {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)

        // Generate 10 random bytes using Swift's cross-platform RNG
        var rng = SystemRandomNumberGenerator()
        var randomBytes = [UInt8](repeating: 0, count: 10)
        for i in 0..<10 {
            randomBytes[i] = UInt8.random(in: 0...255, using: &rng)
        }

        // First 64 bits: timestamp (48 bits) + random (16 bits)
        let high = (timestamp << 16) | (UInt64(randomBytes[0]) << 8) | UInt64(randomBytes[1])

        // Last 64 bits: random (64 bits)
        let low = randomBytes[2...9].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }

        self.rawValue = (high, low)
    }

    /// Creates a ULID from a string representation
    ///
    /// - Parameter string: A 26-character Crockford's Base32 encoded string
    /// - Returns: nil if the string is invalid
    public init?(ulidString string: String) {
        guard string.count == 26 else { return nil }

        let chars = Array(string)
        var values: [UInt8] = []
        for char in chars {
            guard let value = Self.decodingMap[char] else { return nil }
            values.append(value)
        }

        // Check that the padding bits are 0 (first char should be 0-7, i.e., top 2 bits are 0)
        guard values[0] <= 7 else { return nil }

        // Reconstruct high (64 bits) from chars 0-12 + 1 bit from char 13
        // 128 bits are encoded into 130 bits (26 chars × 5 bits), with 2 padding bits at MSB
        var high: UInt64 = 0
        high |= UInt64(values[0]) << 61       // 3 bits at positions 63-61
        high |= UInt64(values[1]) << 56       // 5 bits at positions 60-56
        high |= UInt64(values[2]) << 51       // 5 bits at positions 55-51
        high |= UInt64(values[3]) << 46       // 5 bits at positions 50-46
        high |= UInt64(values[4]) << 41       // 5 bits at positions 45-41
        high |= UInt64(values[5]) << 36       // 5 bits at positions 40-36
        high |= UInt64(values[6]) << 31       // 5 bits at positions 35-31
        high |= UInt64(values[7]) << 26       // 5 bits at positions 30-26
        high |= UInt64(values[8]) << 21       // 5 bits at positions 25-21
        high |= UInt64(values[9]) << 16       // 5 bits at positions 20-16
        high |= UInt64(values[10]) << 11      // 5 bits at positions 15-11
        high |= UInt64(values[11]) << 6       // 5 bits at positions 10-6
        high |= UInt64(values[12]) << 1       // 5 bits at positions 5-1
        high |= UInt64(values[13] >> 4)       // 1 bit at position 0

        // Reconstruct low (64 bits) from char 13's bottom 4 bits + chars 14-25
        var low: UInt64 = 0
        low |= UInt64(values[13] & 0xF) << 60 // 4 bits at positions 63-60
        low |= UInt64(values[14]) << 55       // 5 bits at positions 59-55
        low |= UInt64(values[15]) << 50       // 5 bits at positions 54-50
        low |= UInt64(values[16]) << 45       // 5 bits at positions 49-45
        low |= UInt64(values[17]) << 40       // 5 bits at positions 44-40
        low |= UInt64(values[18]) << 35       // 5 bits at positions 39-35
        low |= UInt64(values[19]) << 30       // 5 bits at positions 34-30
        low |= UInt64(values[20]) << 25       // 5 bits at positions 29-25
        low |= UInt64(values[21]) << 20       // 5 bits at positions 24-20
        low |= UInt64(values[22]) << 15       // 5 bits at positions 19-15
        low |= UInt64(values[23]) << 10       // 5 bits at positions 14-10
        low |= UInt64(values[24]) << 5        // 5 bits at positions 9-5
        low |= UInt64(values[25])             // 5 bits at positions 4-0

        self.rawValue = (high, low)
    }

    /// Creates a ULID from raw bytes
    ///
    /// - Parameter bytes: 16 bytes representing the ULID
    public init(bytes: [UInt8]) {
        precondition(bytes.count == 16, "ULID requires exactly 16 bytes")

        let high = bytes[0..<8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let low = bytes[8..<16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }

        self.rawValue = (high, low)
    }

    /// The ULID as a 26-character string (Crockford's Base32)
    public var ulidString: String {
        var result = [Character](repeating: "0", count: 26)
        let (high, low) = rawValue

        // Encode 128 bits into 26 characters (5 bits each, 130 bits capacity)
        // 2 bits of padding at MSB, then 128 bits of data
        // high contains bits 127-64, low contains bits 63-0

        // Char 0: 2 padding bits + bits 127-125 (3 most significant bits of high)
        result[0] = Self.encodingChars[Int(high >> 61)]

        // Chars 1-12: remaining bits from high (60 bits = 12 chars × 5 bits)
        result[1] = Self.encodingChars[Int((high >> 56) & 0x1F)]
        result[2] = Self.encodingChars[Int((high >> 51) & 0x1F)]
        result[3] = Self.encodingChars[Int((high >> 46) & 0x1F)]
        result[4] = Self.encodingChars[Int((high >> 41) & 0x1F)]
        result[5] = Self.encodingChars[Int((high >> 36) & 0x1F)]
        result[6] = Self.encodingChars[Int((high >> 31) & 0x1F)]
        result[7] = Self.encodingChars[Int((high >> 26) & 0x1F)]
        result[8] = Self.encodingChars[Int((high >> 21) & 0x1F)]
        result[9] = Self.encodingChars[Int((high >> 16) & 0x1F)]
        result[10] = Self.encodingChars[Int((high >> 11) & 0x1F)]
        result[11] = Self.encodingChars[Int((high >> 6) & 0x1F)]
        result[12] = Self.encodingChars[Int((high >> 1) & 0x1F)]

        // Char 13: 1 bit from high + 4 bits from low
        result[13] = Self.encodingChars[Int(((high & 1) << 4) | (low >> 60))]

        // Chars 14-25: remaining bits from low (60 bits = 12 chars × 5 bits)
        result[14] = Self.encodingChars[Int((low >> 55) & 0x1F)]
        result[15] = Self.encodingChars[Int((low >> 50) & 0x1F)]
        result[16] = Self.encodingChars[Int((low >> 45) & 0x1F)]
        result[17] = Self.encodingChars[Int((low >> 40) & 0x1F)]
        result[18] = Self.encodingChars[Int((low >> 35) & 0x1F)]
        result[19] = Self.encodingChars[Int((low >> 30) & 0x1F)]
        result[20] = Self.encodingChars[Int((low >> 25) & 0x1F)]
        result[21] = Self.encodingChars[Int((low >> 20) & 0x1F)]
        result[22] = Self.encodingChars[Int((low >> 15) & 0x1F)]
        result[23] = Self.encodingChars[Int((low >> 10) & 0x1F)]
        result[24] = Self.encodingChars[Int((low >> 5) & 0x1F)]
        result[25] = Self.encodingChars[Int(low & 0x1F)]

        return String(result)
    }

    /// The ULID as raw bytes (16 bytes)
    public var bytes: [UInt8] {
        let (high, low) = rawValue
        var result = [UInt8](repeating: 0, count: 16)

        for i in 0..<8 {
            result[7 - i] = UInt8(high >> (i * 8) & 0xFF)
        }
        for i in 0..<8 {
            result[15 - i] = UInt8(low >> (i * 8) & 0xFF)
        }

        return result
    }

    /// The timestamp component (milliseconds since Unix epoch)
    public var timestamp: UInt64 {
        rawValue.0 >> 16
    }

    /// The timestamp as a Date
    public var date: Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        ulidString
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let ulid = ULID(ulidString: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ULID string: \(string)"
            )
        }
        self = ulid
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ulidString)
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.0)
        hasher.combine(rawValue.1)
    }

    // MARK: - Equatable

    public static func == (lhs: ULID, rhs: ULID) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

// MARK: - Comparable

extension ULID: Comparable {
    public static func < (lhs: ULID, rhs: ULID) -> Bool {
        if lhs.rawValue.0 != rhs.rawValue.0 {
            return lhs.rawValue.0 < rhs.rawValue.0
        }
        return lhs.rawValue.1 < rhs.rawValue.1
    }
}

// MARK: - ExpressibleByStringLiteral

extension ULID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        guard let ulid = ULID(ulidString: value) else {
            fatalError("Invalid ULID string literal: \(value)")
        }
        self = ulid
    }
}
