// RelationshipIndexKind.swift
// Relationship - Cross-type index kind for relationship queries
//
// Enables efficient queries across relationships without JOINs.

import Core

// MARK: - RelationshipIndexKind

/// Cross-type index kind for relationship queries
///
/// Creates indexes that span relationships, enabling efficient queries like:
/// "Find Orders where Customer.name = 'Alice'"
///
/// ## Index Structure
/// ```
/// Key: [indexSubspace]/[relatedField1]/.../[primaryKey] = ''
/// ```
///
/// ## Usage
///
/// ```swift
/// @Persistable
/// struct Order {
///     var id: String
///     var total: Double
///
///     @Relationship(Customer.self, indexFields: [\.name])
///     var customerID: String?
/// }
/// ```
///
/// The `@Relationship` macro with `indexFields` generates this index automatically.
public struct RelationshipIndexKind<Root: Persistable, Related: Persistable>: IndexKind {
    // MARK: - IndexKind Protocol

    public static var identifier: String { "relationship" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    // MARK: - Properties (stored as strings for Codable)

    /// FK field name (e.g., "customerID")
    public let foreignKeyFieldName: String

    /// Related type name (e.g., "Customer")
    public let relatedTypeName: String

    /// Related field names from Related type (e.g., ["name"])
    public let relatedFieldNames: [String]

    /// Whether To-Many relationship
    public let isToMany: Bool

    // MARK: - Computed Properties

    /// Relationship property name (derived from FK)
    /// "customerID" → "customer", "orderIDs" → "orders"
    public var relationshipPropertyName: String {
        if isToMany {
            let base = foreignKeyFieldName.replacingOccurrences(of: "IDs", with: "")
            return base + "s"
        } else {
            return foreignKeyFieldName.replacingOccurrences(of: "ID", with: "")
        }
    }

    // MARK: - IndexKind Requirements

    public var fieldNames: [String] {
        relatedFieldNames.map { "\(relationshipPropertyName).\($0)" }
    }

    public var indexName: String {
        let allNames = [relationshipPropertyName] + relatedFieldNames
        return "\(Root.persistableType)_\(allNames.joined(separator: "_"))"
    }

    // MARK: - Initialization (To-One Optional)

    public init(
        foreignKey: KeyPath<Root, String?>,
        relatedFields: [PartialKeyPath<Related>]
    ) {
        self.foreignKeyFieldName = Root.fieldName(for: foreignKey)
        self.relatedTypeName = Related.persistableType
        self.relatedFieldNames = relatedFields.map { Related.fieldName(for: $0) }
        self.isToMany = false
    }

    // MARK: - Initialization (To-One Required)

    public init(
        foreignKey: KeyPath<Root, String>,
        relatedFields: [PartialKeyPath<Related>]
    ) {
        self.foreignKeyFieldName = Root.fieldName(for: foreignKey)
        self.relatedTypeName = Related.persistableType
        self.relatedFieldNames = relatedFields.map { Related.fieldName(for: $0) }
        self.isToMany = false
    }

    // MARK: - Initialization (To-Many)

    public init(
        foreignKey: KeyPath<Root, [String]>,
        relatedFields: [PartialKeyPath<Related>]
    ) {
        self.foreignKeyFieldName = Root.fieldName(for: foreignKey)
        self.relatedTypeName = Related.persistableType
        self.relatedFieldNames = relatedFields.map { Related.fieldName(for: $0) }
        self.isToMany = true
    }

    // MARK: - Initialization (String-based for Codable)

    public init(
        foreignKeyFieldName: String,
        relatedTypeName: String,
        relatedFieldNames: [String],
        isToMany: Bool
    ) {
        self.foreignKeyFieldName = foreignKeyFieldName
        self.relatedTypeName = relatedTypeName
        self.relatedFieldNames = relatedFieldNames
        self.isToMany = isToMany
    }

    // MARK: - Validation

    public static func validateTypes(_ types: [Any.Type]) throws {
        for type in types {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Relationship index requires Comparable types"
                )
            }
        }
    }

    // MARK: - Utility

    /// Check if this index uses any of the specified related fields
    public func usesAnyRelatedField(from changedFields: Set<String>) -> Bool {
        !changedFields.isDisjoint(with: relatedFieldNames)
    }
}

// MARK: - CustomStringConvertible

extension RelationshipIndexKind: CustomStringConvertible {
    public var description: String {
        "RelationshipIndexKind<\(Root.persistableType), \(relatedTypeName)>(fk: \(foreignKeyFieldName), fields: \(relatedFieldNames))"
    }
}
