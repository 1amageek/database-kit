import DatabaseValue
import Foundation
import QueryIR
import QueryIRFoundation
import Testing

@Suite("QueryIR literal value conversion")
struct LiteralValueConversionTests {
    @Test("unsigned integers retain their full range")
    func unsignedIntegerRetainsFullRange() {
        #expect(UInt64.max.databaseLiteral == .uint(UInt64.max))
    }

    @Test("Decimal converts without floating-point loss")
    func decimalRetainsExactValue() throws {
        let value = try #require(Decimal(string: "1234567890.123456789"))

        #expect(
            try value.databaseLiteral
                == .decimal(coefficient: 1_234_567_890_123_456_789, scale: 9)
        )
    }

    @Test("UUID retains its canonical byte identity")
    func uuidRetainsCanonicalIdentity() throws {
        let value = try #require(UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff"))

        #expect(
            try value.databaseLiteral
                == .uuid(
                    DatabaseUUID(
                        high: 0x0011_2233_4455_6677,
                        low: 0x8899_AABB_CCDD_EEFF
                    )
                )
        )
    }

    @Test("Decimal rejects values outside the canonical coefficient range")
    func decimalRejectsOutOfRangeValue() throws {
        let value = try #require(Decimal(string: "9223372036854775808"))

        #expect(throws: DatabaseLiteralConversionError.decimalOutOfRange) {
            try value.databaseLiteral
        }
    }

    @Test("Decimal rejects NaN")
    func decimalRejectsNaN() {
        #expect(throws: DatabaseLiteralConversionError.nonFiniteDecimal) {
            try Decimal.nan.databaseLiteral
        }
    }

    @Test("Date rejects non-finite timestamps")
    func dateRejectsNonFiniteTimestamp() {
        let value = Date(timeIntervalSince1970: .infinity)

        #expect(throws: DatabaseLiteralConversionError.nonFiniteTimestamp) {
            try value.databaseLiteral
        }
    }

    @Test("Date canonicalizes negative fractional seconds")
    func dateCanonicalizesNegativeFraction() throws {
        let value = Date(timeIntervalSince1970: -0.25)

        #expect(
            try value.databaseLiteral
                == .timestamp(
                    DatabaseTimestamp(
                        secondsSinceUnixEpoch: -1,
                        nanoseconds: 750_000_000
                    )
                )
        )
    }

    @Test("Data is retained as borrowed database bytes")
    func dataRetainsBorrowableStorage() throws {
        let value = Data([0x00, 0x7F, 0xFF])

        let literal = try value.databaseLiteral
        guard case .binary(let bytes) = literal else {
            Issue.record("Expected a binary literal")
            return
        }
        #expect(Array(bytes) == [0x00, 0x7F, 0xFF])
    }
}
