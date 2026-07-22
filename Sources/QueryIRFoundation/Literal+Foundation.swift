import DatabaseValue
import Foundation
import QueryIR

extension Data: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .binary(
            DatabaseBytes(
                retaining: RetainedDataByteOwner(data: self)
            )
        )
    }
}

extension Decimal: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        get throws(DatabaseLiteralConversionError) {
            var value = self
            guard !value.isNaN else {
                throw .nonFiniteDecimal
            }
            let lexicalForm = NSDecimalString(
                &value,
                Locale(identifier: "en_US_POSIX")
            )
            guard let literal = Literal.parseDecimal(lexicalForm) else {
                throw .decimalOutOfRange
            }
            return literal
        }
    }
}

extension Date: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        get throws(DatabaseLiteralConversionError) {
            let interval = timeIntervalSince1970
            guard interval.isFinite else {
                throw .nonFiniteTimestamp
            }
            guard var seconds = Int64(exactly: interval.rounded(.down)) else {
                throw .timestampOutOfRange
            }

            var nanoseconds = Int64(
                ((interval - Double(seconds)) * 1_000_000_000).rounded()
            )
            if nanoseconds == 1_000_000_000 {
                let incremented = seconds.addingReportingOverflow(1)
                guard !incremented.overflow else {
                    throw .timestampOutOfRange
                }
                seconds = incremented.partialValue
                nanoseconds = 0
            }
            guard let canonicalNanoseconds = UInt32(exactly: nanoseconds) else {
                throw .timestampOutOfRange
            }
            return .timestamp(
                DatabaseTimestamp(
                    secondsSinceUnixEpoch: seconds,
                    nanoseconds: canonicalNanoseconds
                )
            )
        }
    }
}

extension UUID: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        withUnsafeBytes(of: uuid) { bytes in
            var high: UInt64 = 0
            var low: UInt64 = 0
            for byteOffset in 0..<16 {
                if byteOffset < 8 {
                    high = (high << 8) | UInt64(bytes[byteOffset])
                } else {
                    low = (low << 8) | UInt64(bytes[byteOffset])
                }
            }
            return .uuid(DatabaseUUID(high: high, low: low))
        }
    }
}
