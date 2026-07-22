import DatabaseValue

public enum OWLRDFLexicalForm {
    public static func floatingPoint(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value == .infinity { return "INF" }
        if value == -.infinity { return "-INF" }
        return String(value)
    }

    public static func dateTime(_ value: DatabaseTimestamp) throws -> String {
        try DatabaseXSDDateTimeCodec.format(timestamp: value)
    }

    public static func date(_ value: DatabaseDate) throws -> String {
        try DatabaseXSDDateTimeCodec.format(date: value)
    }
}
