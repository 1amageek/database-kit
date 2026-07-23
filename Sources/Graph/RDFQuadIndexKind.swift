import Core
import DatabaseValue

/// Declarative metadata for a canonical RDF dataset index.
///
/// Entities remain the source of truth. The execution layer maintains six
/// derived orderings in the same transaction as the entity mutation.
public struct RDFQuadIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "rdf_quad" }
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    public let subjectField: String
    public let predicateField: String
    public let objectField: String
    public let graphField: String?

    public var fieldNames: [String] {
        var fields = [subjectField, predicateField, objectField]
        if let graphField {
            fields.append(graphField)
        }
        return fields
    }

    public var indexName: String {
        let components = fieldNames.map {
            $0.split(separator: ".").joined(separator: "_")
        }
        return ([Root.persistableType, "rdf_quad"] + components)
            .joined(separator: "_")
    }

    public init(
        subject: KeyPath<Root, DatabaseRDFTerm>,
        predicate: KeyPath<Root, DatabaseRDFTerm>,
        object: KeyPath<Root, DatabaseRDFTerm>
    ) {
        self.subjectField = Root.fieldName(for: subject)
        self.predicateField = Root.fieldName(for: predicate)
        self.objectField = Root.fieldName(for: object)
        self.graphField = nil
    }

    public init(
        subject: KeyPath<Root, DatabaseRDFTerm>,
        predicate: KeyPath<Root, DatabaseRDFTerm>,
        object: KeyPath<Root, DatabaseRDFTerm>,
        graph: KeyPath<Root, DatabaseRDFTerm>
    ) {
        self.subjectField = Root.fieldName(for: subject)
        self.predicateField = Root.fieldName(for: predicate)
        self.objectField = Root.fieldName(for: object)
        self.graphField = Root.fieldName(for: graph)
    }

    public init(
        subject: KeyPath<Root, DatabaseRDFTerm>,
        predicate: KeyPath<Root, DatabaseRDFTerm>,
        object: KeyPath<Root, DatabaseRDFTerm>,
        graph: KeyPath<Root, DatabaseRDFTerm?>
    ) {
        self.subjectField = Root.fieldName(for: subject)
        self.predicateField = Root.fieldName(for: predicate)
        self.objectField = Root.fieldName(for: object)
        self.graphField = Root.fieldName(for: graph)
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count == 3 || types.count == 4 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 4,
                actual: types.count
            )
        }

        for type in types.prefix(3) where type != DatabaseRDFTerm.self {
            throw IndexTypeValidationError.unsupportedType(
                index: identifier,
                type: type,
                reason: "subject, predicate, and object fields must be DatabaseRDFTerm"
            )
        }

        if types.count == 4 {
            let graphType = types[3]
            guard graphType == DatabaseRDFTerm.self
                    || graphType == Optional<DatabaseRDFTerm>.self else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: graphType,
                    reason: "graph field must be DatabaseRDFTerm or Optional<DatabaseRDFTerm>"
                )
            }
        }
    }
}

extension RDFQuadIndexKind {
    /// Builds the canonical schema value without creating a concrete index
    /// kind instance. Runtime schema boundaries consume this representation.
    public static func canonical(
        subject: KeyPath<Root, DatabaseRDFTerm>,
        predicate: KeyPath<Root, DatabaseRDFTerm>,
        object: KeyPath<Root, DatabaseRDFTerm>,
        graph: KeyPath<Root, DatabaseRDFTerm>
    ) -> IndexKindMetadata {
        IndexKindMetadata(
            identifier: identifier,
            subspaceStructure: subspaceStructure,
            fieldNames: [
                Root.fieldName(for: subject),
                Root.fieldName(for: predicate),
                Root.fieldName(for: object),
                Root.fieldName(for: graph),
            ],
            metadata: [:]
        )
    }

    /// Builds canonical metadata for a nullable graph field.
    public static func canonical(
        subject: KeyPath<Root, DatabaseRDFTerm>,
        predicate: KeyPath<Root, DatabaseRDFTerm>,
        object: KeyPath<Root, DatabaseRDFTerm>,
        graph: KeyPath<Root, DatabaseRDFTerm?>
    ) -> IndexKindMetadata {
        IndexKindMetadata(
            identifier: identifier,
            subspaceStructure: subspaceStructure,
            fieldNames: [
                Root.fieldName(for: subject),
                Root.fieldName(for: predicate),
                Root.fieldName(for: object),
                Root.fieldName(for: graph),
            ],
            metadata: [:]
        )
    }

    /// Builds canonical metadata for the default graph.
    public static func canonical(
        subject: KeyPath<Root, DatabaseRDFTerm>,
        predicate: KeyPath<Root, DatabaseRDFTerm>,
        object: KeyPath<Root, DatabaseRDFTerm>
    ) -> IndexKindMetadata {
        IndexKindMetadata(
            identifier: identifier,
            subspaceStructure: subspaceStructure,
            fieldNames: [
                Root.fieldName(for: subject),
                Root.fieldName(for: predicate),
                Root.fieldName(for: object),
            ],
            metadata: [:]
        )
    }
}
