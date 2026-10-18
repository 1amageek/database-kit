/// Validated byte-level options with format-specific defaults resolved once.
public struct SQLCopyOptions: Sendable, Hashable {
    public let format: SQLCopyFormat
    public let delimiter: String
    public let null: String
    public let header: Bool
    public let quote: String
    public let escape: String

    public init(format: SQLCopyFormat = .text, delimiter: String? = nil,
                null: String? = nil, header: Bool = false, quote: String? = nil,
                escape: String? = nil) throws(QueryStructuralValidationError) {
        let delimiter = delimiter ?? (format == .text ? "\t" : ",")
        let null = null ?? (format == .text ? "\\N" : "")
        let resolvedQuote = quote ?? "\""
        let resolvedEscape = escape ?? resolvedQuote
        guard Self.singleByte(delimiter), !null.utf8.contains(0),
              !null.utf8.contains(10), !null.utf8.contains(13),
              !null.utf8.contains(delimiter.utf8.first!) else { throw .invalidSQLControl }
        switch format {
        case .text:
            guard !header, quote == nil, escape == nil,
                  let byte = delimiter.utf8.first,
                  byte != 92, byte != 46, !(48...57).contains(byte), !(97...122).contains(byte) else { throw .invalidSQLControl }
        case .csv:
            guard Self.singleByte(resolvedQuote), Self.singleByte(resolvedEscape),
                  delimiter != resolvedQuote, !null.utf8.contains(resolvedQuote.utf8.first!) else {
                throw .invalidSQLControl
            }
        }
        self.format = format; self.delimiter = delimiter; self.null = null
        self.header = header; self.quote = resolvedQuote; self.escape = resolvedEscape
    }

    public static let `default` = SQLCopyOptions(defaultText: ())
    private init(defaultText: Void) {
        format = .text; delimiter = "\t"; null = "\\N"; header = false; quote = "\""; escape = "\""
    }
    private static func singleByte(_ value: String) -> Bool {
        value.utf8.count == 1 && value.utf8.first != 0 && value.utf8.first != 10 && value.utf8.first != 13
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.format == rhs.format && lhs.header == rhs.header
            && SQLDDLIdentity.equal(lhs.delimiter, rhs.delimiter) && SQLDDLIdentity.equal(lhs.null, rhs.null)
            && SQLDDLIdentity.equal(lhs.quote, rhs.quote) && SQLDDLIdentity.equal(lhs.escape, rhs.escape)
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(format); hasher.combine(header)
        for value in [delimiter, null, quote, escape] { SQLDDLIdentity.hash(value, into: &hasher) }
    }
}
