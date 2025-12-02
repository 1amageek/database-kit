// TripleIndexKind.swift
// Triple - RDF Triple index kind (FDB-independent, iOS-compatible)
//
// Defines metadata for RDF triple indexes using the 3-index pattern
// (SPO/POS/OSP) for efficient graph queries.

import Foundation
import Core

/// RDF Triple index kind
///
/// Indexes triples (Subject-Predicate-Object) using three index orderings
/// for efficient query patterns. Follows the classic 3-index RDF store design.
///
/// **Usage with #Index macro**:
/// ```swift
/// @Persistable
/// struct Statement {
///     var subject: String
///     var predicate: String
///     var object: String
///
///     #Index<Statement>(type: TripleIndexKind(
///         subject: \.subject,
///         predicate: \.predicate,
///         object: \.object
///     ))
/// }
/// ```
///
/// **Key structure** (3 indexes):
/// ```
/// [I]/triple/spo/[subject]/[predicate]/[object]/[id]
/// [I]/triple/pos/[predicate]/[object]/[subject]/[id]
/// [I]/triple/osp/[object]/[subject]/[predicate]/[id]
/// ```
///
/// **Query patterns**:
/// - SPO: S??, SP?, SPO queries
/// - POS: ?P?, ?PO queries
/// - OSP: ??O queries
public struct TripleIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "triple" }
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    public let subjectField: String
    public let predicateField: String
    public let objectField: String

    /// All field names for IndexKind protocol
    public var fieldNames: [String] {
        [subjectField, predicateField, objectField]
    }

    /// Default index name: "{TypeName}_triple_{subject}_{predicate}_{object}"
    public var indexName: String {
        let s = subjectField.replacingOccurrences(of: ".", with: "_")
        let p = predicateField.replacingOccurrences(of: ".", with: "_")
        let o = objectField.replacingOccurrences(of: ".", with: "_")
        return "\(Root.persistableType)_triple_\(s)_\(p)_\(o)"
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 3 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 3,
                actual: types.count
            )
        }
        let names = ["subject", "predicate", "object"]
        for (index, type) in types.prefix(3).enumerated() {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "\(names[index]) field must be Comparable"
                )
            }
        }
    }

    /// Initialize with KeyPaths
    public init(
        subject: PartialKeyPath<Root>,
        predicate: PartialKeyPath<Root>,
        object: PartialKeyPath<Root>
    ) {
        self.subjectField = Root.fieldName(for: subject)
        self.predicateField = Root.fieldName(for: predicate)
        self.objectField = Root.fieldName(for: object)
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(
        subjectField: String,
        predicateField: String,
        objectField: String
    ) {
        self.subjectField = subjectField
        self.predicateField = predicateField
        self.objectField = objectField
    }
}

// MARK: - Codable

extension TripleIndexKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case subjectField, predicateField, objectField
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.subjectField = try container.decode(String.self, forKey: .subjectField)
        self.predicateField = try container.decode(String.self, forKey: .predicateField)
        self.objectField = try container.decode(String.self, forKey: .objectField)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subjectField, forKey: .subjectField)
        try container.encode(predicateField, forKey: .predicateField)
        try container.encode(objectField, forKey: .objectField)
    }
}

// MARK: - Hashable

extension TripleIndexKind: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(subjectField)
        hasher.combine(predicateField)
        hasher.combine(objectField)
    }

    public static func == (lhs: TripleIndexKind, rhs: TripleIndexKind) -> Bool {
        lhs.subjectField == rhs.subjectField &&
        lhs.predicateField == rhs.predicateField &&
        lhs.objectField == rhs.objectField
    }
}

/// Triple index ordering
public enum TripleIndexOrder: String, Sendable, Codable, CaseIterable {
    case spo  // Subject-Predicate-Object
    case pos  // Predicate-Object-Subject
    case osp  // Object-Subject-Predicate
}
