import DatabaseTypes

/// One supplied query value addressable by position and optionally by name.
public struct QueryParameter: Sendable, Hashable {
    /// The one-based positional address used by query-language placeholders.
    public let position: UInt32

    /// An optional named address without a query-language prefix.
    public let name: String?

    public let value: FieldValue

    public init(
        position: UInt32,
        name: String? = nil,
        value: FieldValue
    ) {
        self.position = position
        self.name = name
        self.value = value
    }
}
