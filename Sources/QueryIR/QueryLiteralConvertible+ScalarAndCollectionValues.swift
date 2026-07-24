extension Literal: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        self
    }
}

extension Bool: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .bool(self)
    }
}

extension Int: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .int(Int64(self))
    }
}

extension Int8: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .int(Int64(self))
    }
}

extension Int16: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .int(Int64(self))
    }
}

extension Int32: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .int(Int64(self))
    }
}

extension Int64: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .int(self)
    }
}

extension UInt: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .uint(UInt64(self))
    }
}

extension UInt8: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .uint(UInt64(self))
    }
}

extension UInt16: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .uint(UInt64(self))
    }
}

extension UInt32: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .uint(UInt64(self))
    }
}

extension UInt64: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .uint(self)
    }
}

extension Float: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .double(Double(self))
    }
}

extension Double: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .double(self)
    }
}

extension String: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        .string(self)
    }
}

extension Optional: QueryLiteralConvertible where Wrapped: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        get throws(QueryLiteralConversionError) {
            switch self {
            case .some(let value):
                return try value.queryLiteral
            case .none:
                return .null
            }
        }
    }
}

extension Array: QueryLiteralConvertible where Element: QueryLiteralConvertible {
    public var queryLiteral: Literal {
        get throws(QueryLiteralConversionError) {
            var literals: [Literal] = []
            literals.reserveCapacity(count)
            for value in self {
                literals.append(try value.queryLiteral)
            }
            return .array(literals)
        }
    }
}
