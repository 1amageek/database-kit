import DatabaseValue

extension DatabaseDate: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .date(self)
    }
}

extension DatabaseTimestamp: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .timestamp(self)
    }
}

extension DatabaseBytes: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .binary(self)
    }
}

extension DatabaseUUID: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .uuid(self)
    }
}

extension DatabaseRDFTerm: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .rdfTerm(self)
    }
}

extension DatabaseRDFIRI: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .rdfTerm(.iri(rawValue))
    }
}

extension DatabaseRDFPredicateIRI: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .rdfTerm(term)
    }
}

extension DatabaseRDFLiteral: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .rdfTerm(.literal(self))
    }
}

extension DatabaseExactDecimal: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .decimal(coefficient: coefficient, scale: scale)
    }
}

extension FieldValue: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        get throws(DatabaseLiteralConversionError) {
            switch self {
            case .null:
                return .null
            case .bool(let value):
                return .bool(value)
            case .int64(let value):
                return .int(value)
            case .uint64(let value):
                return .uint(value)
            case .double(let value):
                return .double(value)
            case .decimal(let coefficient, let scale):
                return .decimal(coefficient: coefficient, scale: scale)
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
                    literals.append(try value.databaseLiteral)
                }
                return .array(literals)
            case .rdfTerm(let value):
                return .rdfTerm(value)
            case .object, .reference:
                throw .unsupportedFieldValue
            }
        }
    }
}
