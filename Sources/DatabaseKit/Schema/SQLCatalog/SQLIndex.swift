/// Immutable resolved SQL catalog metadata; execution and persistence are runtime-owned.
public struct SQLIndex: Sendable, Hashable {
    public let id: String
    public let namespaceID: String
    public let name: String
    public let relationID: String
    public let keys: [SortKey]
    public let predicate: Expression?
    public let unique: Bool
    public let nulls: SQLNullUniqueness
    public let bindings: [SQLViewColumnBinding]

    public init(id: String, namespaceID: String, name: String, relationID: String, keys: [SortKey], predicate: Expression? = nil, unique: Bool = false, nulls: SQLNullUniqueness = .distinct, bindings: [SQLViewColumnBinding] = []) throws(SQLCatalogError) {
        try SQLIdentifier.validate(id)
        try SQLIdentifier.validate(namespaceID)
        try SQLIdentifier.validate(name)
        try SQLIdentifier.validate(relationID)
        try SQLCatalogMetadataValidation.columns(bindings.map { ($0.id, $0.name) })
        guard !keys.isEmpty else { throw .invalidIndexDefinition }
        self.id = id
        self.namespaceID = namespaceID
        self.name = name
        self.relationID = relationID
        self.keys = keys
        self.predicate = predicate
        self.unique = unique
        self.nulls = nulls
        self.bindings = bindings
    }

    /// Ordered stable key identities, or nil when any key is an expression or lacks a binding.
    public var directColumnIDs: [String]? {
        var result: [String] = []
        result.reserveCapacity(keys.count)
        for key in keys {
            guard case .column(let column) = key.expression,
                let binding = bindings.first(where: { $0.name.utf8.elementsEqual(column.column.utf8) }) else { return nil }
            result.append(binding.id)
        }
        return result
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLIdentifier(value: lhs.id) == SQLIdentifier(value: rhs.id)
            && SQLIdentifier(value: lhs.namespaceID) == SQLIdentifier(value: rhs.namespaceID)
            && SQLIdentifier(value: lhs.name) == SQLIdentifier(value: rhs.name)
            && SQLIdentifier(value: lhs.relationID) == SQLIdentifier(value: rhs.relationID)
            && lhs.keys == rhs.keys
            && lhs.predicate == rhs.predicate
            && lhs.unique == rhs.unique
            && lhs.nulls == rhs.nulls
            && lhs.bindings == rhs.bindings
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SQLIdentifier(value: id))
        hasher.combine(SQLIdentifier(value: namespaceID))
        hasher.combine(SQLIdentifier(value: name))
        hasher.combine(SQLIdentifier(value: relationID))
        hasher.combine(keys)
        hasher.combine(predicate)
        hasher.combine(unique)
        hasher.combine(nulls)
        hasher.combine(bindings)
    }
}
