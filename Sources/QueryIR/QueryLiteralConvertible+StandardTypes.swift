import DatabaseTypes
import DatabaseValue

extension CivilDate: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .date(self)
    }
}

extension Timestamp: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .timestamp(self)
    }
}

extension ByteString: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .binary(self)
    }
}

extension DatabaseTypes.UUID: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .uuid(self)
    }
}

extension RDFTerm: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .rdfTerm(self)
    }
}

extension RDFIRI: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .rdfTerm(.iri(self))
    }
}

extension RDFPredicateIRI: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .rdfTerm(term)
    }
}

extension RDFLiteral: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .rdfTerm(.literal(self))
    }
}

extension ExactDecimal: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .decimal(self)
    }
}

extension FieldValue: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        get throws(QueryLiteralConversionError) {
            switch self {
            case .null:
                return .null
            case .bool(let value):
                return .bool(value)
            case .int8(let value):
                return .int(Int64(value))
            case .int16(let value):
                return .int(Int64(value))
            case .int32(let value):
                return .int(Int64(value))
            case .int64(let value):
                return .int(value)
            case .uint8(let value):
                return .uint(UInt64(value))
            case .uint16(let value):
                return .uint(UInt64(value))
            case .uint32(let value):
                return .uint(UInt64(value))
            case .uint64(let value):
                return .uint(value)
            case .float32(let value):
                return .double(Double(value))
            case .float64(let value):
                return .double(value)
            case .decimal(let value):
                return .decimal(value)
            case .string(let value):
                return .string(value)
            case .bytes(let value):
                return .binary(value)
            case .date(let value):
                return .date(value)
            case .timestamp(let value):
                return .timestamp(value)
            case .uuid(let value):
                return .uuid(value)
            case .array(let values):
                var literals: [Literal] = []
                literals.reserveCapacity(values.count)
                for value in values {
                    literals.append(try value.queryLiteral)
                }
                return .array(literals)
            case .rdfTerm(let value):
                return .rdfTerm(value)
            case .time,
                 .dateTime,
                 .timeSpan,
                 .calendarPeriod,
                 .geographicPoint,
                 .geographicPosition,
                 .vector,
                 .object,
                 .reference:
                throw .unsupportedFieldValue
            }
        }
    }
}
