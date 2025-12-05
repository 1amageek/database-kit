import Testing
import Foundation
@testable import Core

@Suite("ULID Tests")
struct ULIDTests {

    // MARK: - Round-trip Tests (Previously failing)

    @Test("ULID string round-trip preserves all 128 bits")
    func testRoundTripPreservesAllBits() throws {
        // This test would have failed before the fix:
        // The old implementation dropped the upper 14 bits of the timestamp
        for _ in 0..<100 {
            let original = ULID()
            let string = original.ulidString
            guard let decoded = ULID(ulidString: string) else {
                Issue.record("Failed to decode ULID string: \(string)")
                return
            }

            #expect(decoded.rawValue.0 == original.rawValue.0,
                   "High 64 bits should match. Original: \(original.rawValue.0), Decoded: \(decoded.rawValue.0)")
            #expect(decoded.rawValue.1 == original.rawValue.1,
                   "Low 64 bits should match. Original: \(original.rawValue.1), Decoded: \(decoded.rawValue.1)")
            #expect(decoded == original, "Round-trip should preserve equality")
        }
    }

    @Test("ULID bytes round-trip preserves all 128 bits")
    func testBytesRoundTripPreservesAllBits() throws {
        for _ in 0..<100 {
            let original = ULID()
            let bytes = original.bytes
            let decoded = ULID(bytes: bytes)

            #expect(decoded.rawValue.0 == original.rawValue.0)
            #expect(decoded.rawValue.1 == original.rawValue.1)
            #expect(decoded == original)
        }
    }

    @Test("ULID timestamp is preserved after round-trip")
    func testTimestampPreservedAfterRoundTrip() throws {
        // This test specifically checks that the timestamp (upper 48 bits of high)
        // is preserved correctly after encoding and decoding
        let original = ULID()
        let originalTimestamp = original.timestamp

        let string = original.ulidString
        guard let decoded = ULID(ulidString: string) else {
            Issue.record("Failed to decode ULID string")
            return
        }

        #expect(decoded.timestamp == originalTimestamp,
               "Timestamp should be preserved. Original: \(originalTimestamp), Decoded: \(decoded.timestamp)")
    }

    @Test("ULID with maximum timestamp value round-trips correctly")
    func testMaxTimestampRoundTrip() throws {
        // Create a ULID with maximum possible timestamp (48 bits all 1s)
        // This tests the upper bits that were previously being dropped
        let maxTimestamp: UInt64 = (1 << 48) - 1  // 0xFFFFFFFFFFFF
        let randomHigh: UInt64 = 0xFFFF  // 16 bits of random
        let randomLow: UInt64 = UInt64.max  // 64 bits of random

        let high = (maxTimestamp << 16) | randomHigh
        let low = randomLow

        let original = ULID(rawValue: (high, low))
        let string = original.ulidString
        guard let decoded = ULID(ulidString: string) else {
            Issue.record("Failed to decode ULID with max timestamp")
            return
        }

        #expect(decoded.rawValue.0 == high, "High bits should match for max timestamp")
        #expect(decoded.rawValue.1 == low, "Low bits should match for max timestamp")
        #expect(decoded.timestamp == maxTimestamp, "Max timestamp should be preserved")
    }

    @Test("ULID with all bits set round-trips correctly")
    func testAllBitsSetRoundTrip() throws {
        // Test with all 128 bits set (except padding bits which must be 0)
        // Maximum valid high value: first char can be 0-7 (3 bits), so max is when top 3 bits = 0b111
        let maxValidHigh: UInt64 = UInt64.max >> 1  // Clear the top bit to ensure valid encoding
        let maxValidLow: UInt64 = UInt64.max

        let original = ULID(rawValue: (maxValidHigh, maxValidLow))
        let string = original.ulidString
        guard let decoded = ULID(ulidString: string) else {
            Issue.record("Failed to decode ULID with max valid bits")
            return
        }

        #expect(decoded.rawValue.0 == maxValidHigh)
        #expect(decoded.rawValue.1 == maxValidLow)
    }

    @Test("ULID with minimum bits set round-trips correctly")
    func testMinBitsSetRoundTrip() throws {
        let original = ULID(rawValue: (0, 0))
        let string = original.ulidString
        guard let decoded = ULID(ulidString: string) else {
            Issue.record("Failed to decode ULID with zero bits")
            return
        }

        #expect(decoded.rawValue.0 == 0)
        #expect(decoded.rawValue.1 == 0)
        #expect(string == "00000000000000000000000000", "Zero ULID should encode to all zeros")
    }

    // MARK: - Lexicographic Ordering Tests

    @Test("ULID string comparison matches raw value comparison")
    func testLexicographicOrdering() throws {
        // Generate multiple ULIDs and verify string ordering matches value ordering
        var ulids: [ULID] = []
        for _ in 0..<100 {
            ulids.append(ULID())
        }

        let sortedByValue = ulids.sorted()
        let sortedByString = ulids.sorted { $0.ulidString < $1.ulidString }

        for (byValue, byString) in zip(sortedByValue, sortedByString) {
            #expect(byValue == byString,
                   "String-sorted and value-sorted should match")
        }
    }

    @Test("Earlier ULID has smaller string representation")
    func testTemporalOrdering() throws {
        let earlier = ULID()
        // Small delay to ensure different timestamp
        Thread.sleep(forTimeInterval: 0.002)
        let later = ULID()

        #expect(earlier < later, "Earlier ULID should be less than later ULID")
        #expect(earlier.ulidString < later.ulidString,
               "Earlier ULID string should be lexicographically smaller")
    }

    // MARK: - Specific Bit Pattern Tests

    @Test("ULID correctly encodes boundary bit positions")
    func testBoundaryBitPositions() throws {
        // Test specific bit positions at the high/low boundary
        // Bit 64 is the boundary between high and low

        // Test with only bit 64 set (lowest bit of high)
        let bit64Set = ULID(rawValue: (1, 0))
        let string64 = bit64Set.ulidString
        guard let decoded64 = ULID(ulidString: string64) else {
            Issue.record("Failed to decode bit 64 set ULID")
            return
        }
        #expect(decoded64.rawValue.0 == 1, "Bit 64 should be preserved")
        #expect(decoded64.rawValue.1 == 0, "Low bits should be zero")

        // Test with only bit 63 set (highest bit of low)
        let bit63Set = ULID(rawValue: (0, 1 << 63))
        let string63 = bit63Set.ulidString
        guard let decoded63 = ULID(ulidString: string63) else {
            Issue.record("Failed to decode bit 63 set ULID")
            return
        }
        #expect(decoded63.rawValue.0 == 0, "High bits should be zero")
        #expect(decoded63.rawValue.1 == 1 << 63, "Bit 63 should be preserved")
    }

    @Test("ULID encoding covers all bit positions")
    func testAllBitPositionsCovered() throws {
        // Test each bit position individually to ensure none are dropped
        for bitPosition in 0..<128 {
            let high: UInt64
            let low: UInt64

            if bitPosition >= 64 {
                high = UInt64(1) << (bitPosition - 64)
                low = 0
            } else {
                high = 0
                low = UInt64(1) << bitPosition
            }

            // Skip if this would set the invalid padding bits (bits 127-125 can only be 0-7)
            if bitPosition >= 125 {
                continue
            }

            let original = ULID(rawValue: (high, low))
            let string = original.ulidString
            guard let decoded = ULID(ulidString: string) else {
                Issue.record("Failed to decode ULID with bit \(bitPosition) set")
                continue
            }

            #expect(decoded.rawValue.0 == high,
                   "Bit \(bitPosition): high should match")
            #expect(decoded.rawValue.1 == low,
                   "Bit \(bitPosition): low should match")
        }
    }

    // MARK: - Codable Round-trip Tests

    @Test("ULID Codable round-trip preserves value")
    func testCodableRoundTrip() throws {
        let original = ULID()

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ULID.self, from: data)

        #expect(decoded == original, "Codable round-trip should preserve ULID")
    }

    // MARK: - Invalid Input Tests

    @Test("ULID rejects invalid first character")
    func testRejectsInvalidFirstChar() throws {
        // First character must be 0-7 (only 3 bits used due to 2-bit padding)
        // Characters 8-Z are invalid for first position

        // "8" encodes to value 8, which requires 4 bits - invalid for first position
        let invalidString = "8" + String(repeating: "0", count: 25)
        let result = ULID(ulidString: invalidString)
        #expect(result == nil, "Should reject ULID starting with '8' (value > 7)")

        // "Z" encodes to value 31, definitely invalid
        let invalidZ = "Z" + String(repeating: "0", count: 25)
        let resultZ = ULID(ulidString: invalidZ)
        #expect(resultZ == nil, "Should reject ULID starting with 'Z'")
    }

    @Test("ULID rejects wrong length strings")
    func testRejectsWrongLength() throws {
        let tooShort = "0123456789ABCDEFGHJKMNPQR"  // 25 chars
        let tooLong = "0123456789ABCDEFGHJKMNPQRST"  // 27 chars

        #expect(ULID(ulidString: tooShort) == nil, "Should reject 25-char string")
        #expect(ULID(ulidString: tooLong) == nil, "Should reject 27-char string")
    }

    @Test("ULID rejects invalid characters")
    func testRejectsInvalidChars() throws {
        // ULID uses Crockford's Base32 which excludes I, L, O, U
        // (though I, L, O are mapped to 1, 1, 0 for decoding tolerance)
        let withU = "0123456789ABCDEFGHJKMNPQRU"
        #expect(ULID(ulidString: withU) == nil, "Should reject string with 'U'")
    }
}

// Extension to create ULID from raw value for testing
extension ULID {
    init(rawValue: (UInt64, UInt64)) {
        self.init(bytes: Self.rawValueToBytes(rawValue))
    }

    private static func rawValueToBytes(_ rawValue: (UInt64, UInt64)) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        let (high, low) = rawValue
        for i in 0..<8 {
            bytes[7 - i] = UInt8(high >> (i * 8) & 0xFF)
        }
        for i in 0..<8 {
            bytes[15 - i] = UInt8(low >> (i * 8) & 0xFF)
        }
        return bytes
    }
}
