/// Explicit options for plan inspection and optional measured execution.
public struct SQLExplainOptions: Sendable, Hashable {
    public let analyze: Bool
    public let verbose: Bool
    public let format: SQLExplainFormat
    public init(analyze: Bool = false, verbose: Bool = false, format: SQLExplainFormat = .text) {
        self.analyze = analyze; self.verbose = verbose; self.format = format
    }
}
