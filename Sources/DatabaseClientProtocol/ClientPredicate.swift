import Core

/// Codable predicate AST for client-server query transport
///
/// Mirrors the server-side `Predicate<T>` but without KeyPath closures.
/// Supports `and`, `or`, `not` for composable queries.
///
/// On the server, reconstructed using FieldReader (Layer 2) evaluation path.
public indirect enum ClientPredicate: Sendable, Codable, Hashable {
    case comparison(ClientFieldComparison)
    case and([ClientPredicate])
    case or([ClientPredicate])
    case not(ClientPredicate)
}

/// Single field comparison in a predicate
public struct ClientFieldComparison: Sendable, Codable, Hashable {
    /// Field name (supports dot notation for nested fields: "address.city")
    public let fieldName: String

    /// Comparison operator
    public let op: ComparisonOperator

    /// Value to compare against
    public let value: FieldValue

    public init(fieldName: String, op: ComparisonOperator, value: FieldValue) {
        self.fieldName = fieldName
        self.op = op
        self.value = value
    }
}

/// Sort descriptor for query results
public struct ClientSortDescriptor: Sendable, Codable, Hashable {
    /// Field name to sort by
    public let fieldName: String

    /// Sort order
    public let ascending: Bool

    public init(fieldName: String, ascending: Bool = true) {
        self.fieldName = fieldName
        self.ascending = ascending
    }
}
