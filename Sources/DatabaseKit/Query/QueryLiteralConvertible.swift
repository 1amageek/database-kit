/// A value that can be represented by the canonical QueryIR literal model.
public protocol QueryLiteralConvertible {
    var queryLiteral: Literal {
        get throws(QueryLiteralConversionError)
    }
}
