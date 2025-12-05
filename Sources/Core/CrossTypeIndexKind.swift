// CrossTypeIndexKind.swift
// Core - Cross-Type Index for indexing across relationships
//
// Reference: FDB Record Layer - Joined Index Types
// https://github.com/FoundationDB/fdb-record-layer

// MARK: - CrossTypeIndexKindProtocol

/// Type-erased protocol for accessing CrossTypeIndexKind properties at runtime
///
/// This protocol allows runtime inspection of CrossTypeIndexKind instances
/// without knowing the generic type parameters (Root, Related).
/// Used by database-framework to update cross-type indexes when related items change.
public protocol CrossTypeIndexKindProtocol: IndexKind {
    /// Name of the relationship property (e.g., `"customer"`)
    var relationshipPropertyName: String { get }

    /// Name of the FK field (e.g., `"customerID"` for To-One, `"orderIDs"` for To-Many)
    var foreignKeyFieldName: String { get }

    /// Name of the related Persistable type (e.g., `"Customer"`)
    var relatedTypeName: String { get }

    /// Field names from the related type (e.g., `["name", "tier"]`)
    var relatedFieldNames: [String] { get }

    /// Field names from the local type (e.g., `["total"]`)
    var localFieldNames: [String] { get }
}

// MARK: - CrossTypeIndexKind

/// Index kind for creating indexes that span relationships
///
/// `CrossTypeIndexKind` enables creating indexes that combine fields from
/// a Persistable type with fields from a related type via `@Relationship`.
/// This is similar to FDB Record Layer's "Joined" index types.
///
/// ## Usage
///
/// ```swift
/// @Persistable
/// struct Order {
///     var id: String
///     var total: Double
///
///     @Relationship(inverse: \Customer.orders)
///     var customer: Customer?
///
///     // Cross-Type Index: index orders by customer name and total
///     #Index<Order>(CrossTypeIndexKind(
///         relationship: \.customer,
///         relatedFields: [\Customer.name],
///         localFields: [\.total]
///     ))
/// }
///
/// @Persistable
/// struct Customer {
///     var id: String
///     var name: String
///
///     @Relationship(deleteRule: .cascade, inverse: \Order.customer)
///     var orders: [Order]
/// }
/// ```
///
/// ## Key Structure
///
/// ```
/// [indexSubspace]/[relatedField1]/.../[localField1]/.../[primaryKey] = ''
/// ```
///
/// Example: `Order_customer_name_total/["Alice"]/[99.99]/["O001"]`
///
/// ## Update Behavior
///
/// - **On Order save**: Load Customer, extract `name`, combine with `total`,
///   update index entry.
/// - **On Customer update**: Find all related Orders via inverse relationship,
///   update their Cross-Type index entries.
///
/// ## Type Parameters
///
/// - `Root`: The Persistable type that owns the index (e.g., `Order`)
/// - `Related`: The related Persistable type via `@Relationship` (e.g., `Customer`)
public struct CrossTypeIndexKind<Root: Persistable, Related: Persistable>: CrossTypeIndexKindProtocol {
    // MARK: - IndexKind Protocol

    public static var identifier: String { "cross_type" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    // MARK: - Properties

    /// Name of the relationship property (e.g., `"customer"`)
    public let relationshipPropertyName: String

    /// Name of the FK field (e.g., `"customerID"` for To-One, `"orderIDs"` for To-Many)
    public let foreignKeyFieldName: String

    /// Name of the related Persistable type (e.g., `"Customer"`)
    public let relatedTypeName: String

    /// Field names from the related type (e.g., `["name", "tier"]`)
    public let relatedFieldNames: [String]

    /// Field names from the local (Root) type (e.g., `["total"]`)
    public let localFieldNames: [String]

    // MARK: - IndexKind Requirements

    /// All field names (related + local) for IndexKind protocol
    ///
    /// Related fields are prefixed with the relationship name for uniqueness.
    /// Example: `["customer.name", "customer.tier", "total"]`
    public var fieldNames: [String] {
        let prefixedRelated = relatedFieldNames.map { "\(relationshipPropertyName).\($0)" }
        return prefixedRelated + localFieldNames
    }

    /// Default index name
    ///
    /// Format: `{RootType}_{relationship}_{relatedField1}_{localField1}...`
    /// Example: `Order_customer_name_total`
    public var indexName: String {
        let relatedNames = relatedFieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        let localNames = localFieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        let allNames = [relationshipPropertyName] + relatedNames + localNames
        return "\(Root.persistableType)_\(allNames.joined(separator: "_"))"
    }

    // MARK: - Initialization (Type-Safe with KeyPaths - To-One)

    /// Initialize with KeyPaths for type-safe field references (To-One relationship)
    ///
    /// - Parameters:
    ///   - foreignKey: KeyPath to the FK field in Root (e.g., `\.customerID`)
    ///   - relatedFields: KeyPaths to fields in the Related type to include
    ///   - localFields: KeyPaths to fields in the Root type to include
    ///
    /// ## Example
    ///
    /// ```swift
    /// CrossTypeIndexKind(
    ///     foreignKey: \.customerID,
    ///     relatedFields: [\Customer.name, \Customer.tier],
    ///     localFields: [\.total, \.status]
    /// )
    /// ```
    public init(
        foreignKey: KeyPath<Root, String?>,
        relatedFields: [PartialKeyPath<Related>],
        localFields: [PartialKeyPath<Root>]
    ) {
        let fkFieldName = Root.fieldName(for: foreignKey)
        self.foreignKeyFieldName = fkFieldName
        // Derive relationship property name: "customerID" -> "customer"
        self.relationshipPropertyName = fkFieldName.replacingOccurrences(of: "ID", with: "")
        self.relatedTypeName = Related.persistableType
        self.relatedFieldNames = relatedFields.map { Related.fieldName(for: $0) }
        self.localFieldNames = localFields.map { Root.fieldName(for: $0) }
    }

    // MARK: - Initialization (Type-Safe with KeyPaths - To-Many)

    /// Initialize with KeyPaths for type-safe field references (To-Many relationship)
    ///
    /// - Parameters:
    ///   - foreignKey: KeyPath to the FK array field in Root (e.g., `\.orderIDs`)
    ///   - relatedFields: KeyPaths to fields in the Related type to include
    ///   - localFields: KeyPaths to fields in the Root type to include
    ///
    /// ## Example
    ///
    /// ```swift
    /// CrossTypeIndexKind(
    ///     foreignKey: \.orderIDs,
    ///     relatedFields: [\Order.total],
    ///     localFields: [\.name]
    /// )
    /// ```
    public init(
        foreignKey: KeyPath<Root, [String]>,
        relatedFields: [PartialKeyPath<Related>],
        localFields: [PartialKeyPath<Root>]
    ) {
        let fkFieldName = Root.fieldName(for: foreignKey)
        self.foreignKeyFieldName = fkFieldName
        // Derive relationship property name: "orderIDs" -> "orders"
        let base = fkFieldName.replacingOccurrences(of: "IDs", with: "")
        self.relationshipPropertyName = base + "s"
        self.relatedTypeName = Related.persistableType
        self.relatedFieldNames = relatedFields.map { Related.fieldName(for: $0) }
        self.localFieldNames = localFields.map { Root.fieldName(for: $0) }
    }

    // MARK: - Initialization (String-Based for Codable)

    /// Initialize with field name strings (for Codable reconstruction)
    ///
    /// - Parameters:
    ///   - relationshipPropertyName: Name of the relationship property (e.g., "customer")
    ///   - foreignKeyFieldName: Name of the FK field (e.g., "customerID" or "orderIDs")
    ///   - relatedTypeName: Name of the related Persistable type
    ///   - relatedFieldNames: Field names from the related type
    ///   - localFieldNames: Field names from the local type
    public init(
        relationshipPropertyName: String,
        foreignKeyFieldName: String,
        relatedTypeName: String,
        relatedFieldNames: [String],
        localFieldNames: [String]
    ) {
        self.relationshipPropertyName = relationshipPropertyName
        self.foreignKeyFieldName = foreignKeyFieldName
        self.relatedTypeName = relatedTypeName
        self.relatedFieldNames = relatedFieldNames
        self.localFieldNames = localFieldNames
    }

    // MARK: - Validation

    public static func validateTypes(_ types: [Any.Type]) throws {
        // Cross-type index should have at least one field
        guard !types.isEmpty else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }

        // All fields must be Comparable for index ordering
        for type in types {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Cross-type index requires Comparable types for all fields"
                )
            }
        }
    }

    // MARK: - Utility Methods

    /// Check if this index uses a specific field from the related type
    ///
    /// - Parameter fieldName: The field name to check
    /// - Returns: `true` if the index includes this related field
    public func usesRelatedField(_ fieldName: String) -> Bool {
        relatedFieldNames.contains(fieldName)
    }

    /// Check if this index uses any of the specified fields from the related type
    ///
    /// Used to determine if a related item's change affects this index.
    ///
    /// - Parameter fieldNames: Set of field names that changed
    /// - Returns: `true` if any changed field is used in this index
    public func usesAnyRelatedField(from fieldNames: Set<String>) -> Bool {
        !fieldNames.isDisjoint(with: relatedFieldNames)
    }
}

// MARK: - CustomStringConvertible

extension CrossTypeIndexKind: CustomStringConvertible {
    public var description: String {
        let relatedStr = relatedFieldNames.map { "\(relatedTypeName).\($0)" }.joined(separator: ", ")
        let localStr = localFieldNames.joined(separator: ", ")
        return "CrossTypeIndexKind<\(Root.persistableType), \(relatedTypeName)>(\(relationshipPropertyName): [\(relatedStr)], local: [\(localStr)])"
    }
}

// MARK: - Codable

extension CrossTypeIndexKind: Codable {
    enum CodingKeys: String, CodingKey {
        case relationshipPropertyName
        case foreignKeyFieldName
        case relatedTypeName
        case relatedFieldNames
        case localFieldNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.relationshipPropertyName = try container.decode(String.self, forKey: .relationshipPropertyName)
        self.foreignKeyFieldName = try container.decode(String.self, forKey: .foreignKeyFieldName)
        self.relatedTypeName = try container.decode(String.self, forKey: .relatedTypeName)
        self.relatedFieldNames = try container.decode([String].self, forKey: .relatedFieldNames)
        self.localFieldNames = try container.decode([String].self, forKey: .localFieldNames)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relationshipPropertyName, forKey: .relationshipPropertyName)
        try container.encode(foreignKeyFieldName, forKey: .foreignKeyFieldName)
        try container.encode(relatedTypeName, forKey: .relatedTypeName)
        try container.encode(relatedFieldNames, forKey: .relatedFieldNames)
        try container.encode(localFieldNames, forKey: .localFieldNames)
    }
}

// MARK: - Hashable

extension CrossTypeIndexKind: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(relationshipPropertyName)
        hasher.combine(foreignKeyFieldName)
        hasher.combine(relatedTypeName)
        hasher.combine(relatedFieldNames)
        hasher.combine(localFieldNames)
    }

    public static func == (lhs: CrossTypeIndexKind, rhs: CrossTypeIndexKind) -> Bool {
        lhs.relationshipPropertyName == rhs.relationshipPropertyName &&
        lhs.foreignKeyFieldName == rhs.foreignKeyFieldName &&
        lhs.relatedTypeName == rhs.relatedTypeName &&
        lhs.relatedFieldNames == rhs.relatedFieldNames &&
        lhs.localFieldNames == rhs.localFieldNames
    }
}
