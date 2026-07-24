import DatabaseValue
import DatabaseTypes

public enum OWLRDFLexicalForm {
    public static func floatingPoint(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value == .infinity { return "INF" }
        if value == -.infinity { return "-INF" }
        return String(value)
    }

    public static func dateTime(_ value: Timestamp) throws -> String {
        try XSDDateTimeCodec.format(timestamp: value)
    }

    public static func date(_ value: CivilDate) -> String {
        XSDDateTimeCodec.format(date: value)
    }
}
