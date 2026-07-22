extension Literal: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        self
    }
}

extension Bool: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .bool(self)
    }
}

extension Int: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .int(Int64(self))
    }
}

extension Int8: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .int(Int64(self))
    }
}

extension Int16: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .int(Int64(self))
    }
}

extension Int32: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .int(Int64(self))
    }
}

extension Int64: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .int(self)
    }
}

extension UInt: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .uint(UInt64(self))
    }
}

extension UInt8: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .uint(UInt64(self))
    }
}

extension UInt16: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .uint(UInt64(self))
    }
}

extension UInt32: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .uint(UInt64(self))
    }
}

extension UInt64: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .uint(self)
    }
}

extension Float: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .double(Double(self))
    }
}

extension Double: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .double(self)
    }
}

extension String: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        .string(self)
    }
}

extension Optional: DatabaseLiteralConvertible where Wrapped: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        get throws(DatabaseLiteralConversionError) {
            switch self {
            case .some(let value):
                return try value.databaseLiteral
            case .none:
                return .null
            }
        }
    }
}

extension Array: DatabaseLiteralConvertible where Element: DatabaseLiteralConvertible {
    public var databaseLiteral: Literal {
        get throws(DatabaseLiteralConversionError) {
            var literals: [Literal] = []
            literals.reserveCapacity(count)
            for value in self {
                literals.append(try value.databaseLiteral)
            }
            return .array(literals)
        }
    }
}
