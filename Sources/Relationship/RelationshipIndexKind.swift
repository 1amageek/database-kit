// RelationshipIndexKind.swift
// Relationship - Cross-type index kind for relationship queries
//
// Enables efficient queries across relationships without JOINs.

import Core

// MARK: - RelationshipIndexKind

/// Cross-type index kind for relationship queries
///
/// Creates indexes that span relationships, enabling efficient queries like:
/// "Find Orders where Customer.name = 'Alice' AND Order.total > 100"
///
/// ## Index Structure
/// ```
/// Key: [indexSubspace]/[relatedField1]/.../[localField1]/.../[primaryKey] = ''
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
///     @Relationship(Customer.self, deleteRule: .cascade)
///     var customerID: String?
///
///     static var descriptors: [any Descriptor] {
///         [
///             // Cross-type index for efficient queries
///             IndexDescriptor(
///                 name: "Order_customer_name_total",
///                 kind: RelationshipIndexKind<Order, Customer>(
///                     foreignKey: \.customerID,
///                     relatedFields: [\.name],
///                     localFields: [\.total]
///                 )
///             )
///         ]
///     }
/// }
/// ```
public struct RelationshipIndexKind<Root: Persistable, Related: Persistable>: IndexKind {
    // MARK: - IndexKind Protocol

    public static var identifier: String { "relationship" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    // MARK: - Properties (stored as strings for Codable)

    /// FK field name
    public let foreignKeyFieldName: String

    /// Related type name
    public let relatedTypeName: String

    /// Related field names (from Related type)
    public let relatedFieldNames: [String]

    /// Local field names (from Root type)
    public let localFieldNames: [String]

    /// Whether To-Many relationship
    public let isToMany: Bool

    // MARK: - Computed Properties

    /// Relationship property name (derived from FK)
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
        let prefixed = relatedFieldNames.map { "\(relationshipPropertyName).\($0)" }
        return prefixed + localFieldNames
    }

    public var indexName: String {
        let allNames = [relationshipPropertyName] + relatedFieldNames + localFieldNames
        return "\(Root.persistableType)_\(allNames.joined(separator: "_"))"
    }

    // MARK: - Initialization (To-One Optional)

    public init(
        foreignKey: KeyPath<Root, String?>,
        relatedFields: [PartialKeyPath<Related>],
        localFields: [PartialKeyPath<Root>] = []
    ) {
        self.foreignKeyFieldName = Root.fieldName(for: foreignKey)
        self.relatedTypeName = Related.persistableType
        self.relatedFieldNames = relatedFields.map { Related.fieldName(for: $0) }
        self.localFieldNames = localFields.map { Root.fieldName(for: $0) }
        self.isToMany = false
    }

    // MARK: - Initialization (To-One Required)

    public init(
        foreignKey: KeyPath<Root, String>,
        relatedFields: [PartialKeyPath<Related>],
        localFields: [PartialKeyPath<Root>] = []
    ) {
        self.foreignKeyFieldName = Root.fieldName(for: foreignKey)
        self.relatedTypeName = Related.persistableType
        self.relatedFieldNames = relatedFields.map { Related.fieldName(for: $0) }
        self.localFieldNames = localFields.map { Root.fieldName(for: $0) }
        self.isToMany = false
    }

    // MARK: - Initialization (To-Many)

    public init(
        foreignKey: KeyPath<Root, [String]>,
        relatedFields: [PartialKeyPath<Related>],
        localFields: [PartialKeyPath<Root>] = []
    ) {
        self.foreignKeyFieldName = Root.fieldName(for: foreignKey)
        self.relatedTypeName = Related.persistableType
        self.relatedFieldNames = relatedFields.map { Related.fieldName(for: $0) }
        self.localFieldNames = localFields.map { Root.fieldName(for: $0) }
        self.isToMany = true
    }

    // MARK: - Initialization (String-based for Codable)

    public init(
        foreignKeyFieldName: String,
        relatedTypeName: String,
        relatedFieldNames: [String],
        localFieldNames: [String],
        isToMany: Bool
    ) {
        self.foreignKeyFieldName = foreignKeyFieldName
        self.relatedTypeName = relatedTypeName
        self.relatedFieldNames = relatedFieldNames
        self.localFieldNames = localFieldNames
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
        "RelationshipIndexKind<\(Root.persistableType), \(relatedTypeName)>(fk: \(foreignKeyFieldName), related: \(relatedFieldNames), local: \(localFieldNames))"
    }
}
