import DatabaseTypes
import DatabaseTypesFoundation
import DatabaseValue
import Foundation
import QueryIR

extension Data: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .binary(ByteString(retaining: self))
    }
}

extension Decimal: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        get throws(DatabaseLiteralConversionError) {
            do {
                return .decimal(try ExactDecimal(self))
            } catch .nonFiniteValue {
                throw .nonFiniteDecimal
            } catch {
                throw .decimalOutOfRange
            }
        }
    }
}

extension Date: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        get throws(DatabaseLiteralConversionError) {
            do {
                return .timestamp(try Timestamp(self))
            } catch let error {
                switch error {
                case .nonFiniteDate:
                    throw .nonFiniteTimestamp
                case .valueOutOfRange:
                    throw .timestampOutOfRange
                }
            }
        }
    }
}

extension Foundation.UUID: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .uuid(DatabaseTypes.UUID(self))
    }
}
