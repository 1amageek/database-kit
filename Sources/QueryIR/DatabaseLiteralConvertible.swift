/// A value that can be represented by the canonical QueryIR literal model.
public protocol DatabaseLiteralConvertible {
    var databaseLiteral: Literal {
        get throws(DatabaseLiteralConversionError)
    }
}
