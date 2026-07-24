import DatabaseTypes

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
            var steps: [FieldValueLiteralConversionStep] = [.value(self)]
            var results: [Literal] = []

            while let step = steps.popLast() {
                switch step {
                case .value(let value):
                    switch value {
                    case .null:
                        results.append(.null)
                    case .bool(let value):
                        results.append(.bool(value))
                    case .int8(let value):
                        results.append(.int(Int64(value)))
                    case .int16(let value):
                        results.append(.int(Int64(value)))
                    case .int32(let value):
                        results.append(.int(Int64(value)))
                    case .int64(let value):
                        results.append(.int(value))
                    case .uint8(let value):
                        results.append(.uint(UInt64(value)))
                    case .uint16(let value):
                        results.append(.uint(UInt64(value)))
                    case .uint32(let value):
                        results.append(.uint(UInt64(value)))
                    case .uint64(let value):
                        results.append(.uint(value))
                    case .float32(let value):
                        results.append(.double(Double(value)))
                    case .float64(let value):
                        results.append(.double(value))
                    case .decimal(let value):
                        results.append(.decimal(value))
                    case .string(let value):
                        results.append(.string(value))
                    case .bytes(let value):
                        results.append(.binary(value))
                    case .date(let value):
                        results.append(.date(value))
                    case .timestamp(let value):
                        results.append(.timestamp(value))
                    case .uuid(let value):
                        results.append(.uuid(value))
                    case .array(let values):
                        steps.append(.assembleArray(values.count))
                        for value in values.reversed() {
                            steps.append(.value(value))
                        }
                    case .rdfTerm(let value):
                        results.append(.rdfTerm(value))
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
                case .assembleArray(let count):
                    guard results.count >= count else {
                        throw .unsupportedFieldValue
                    }
                    let start = results.count - count
                    let values = Array(results[start...])
                    results.removeLast(count)
                    results.append(.array(values))
                }
            }

            guard results.count == 1, let result = results.last else {
                throw .unsupportedFieldValue
            }
            return result
        }
    }
}

private enum FieldValueLiteralConversionStep {
    case value(FieldValue)
    case assembleArray(Int)
}
