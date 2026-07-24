import DatabaseTypes
import DatabaseTypesFoundation
import DatabaseValue
import Foundation
import QueryIR

extension Data: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .binary(ByteString(retaining: self))
    }
}

extension Decimal: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        get throws(QueryLiteralConversionError) {
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

extension Date: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        get throws(QueryLiteralConversionError) {
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

extension Foundation.UUID: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .uuid(DatabaseTypes.UUID(self))
    }
}
