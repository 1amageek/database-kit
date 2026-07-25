import DatabaseTypes

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
        subject: KeyPath<Root, RDFTerm>,
        predicate: KeyPath<Root, RDFTerm>,
        object: KeyPath<Root, RDFTerm>
    ) {
        self.subjectField = Root.fieldName(for: subject)
        self.predicateField = Root.fieldName(for: predicate)
        self.objectField = Root.fieldName(for: object)
        self.graphField = nil
    }

    public init(
        subject: KeyPath<Root, RDFTerm>,
        predicate: KeyPath<Root, RDFTerm>,
        object: KeyPath<Root, RDFTerm>,
        graph: KeyPath<Root, RDFTerm>
    ) {
        self.subjectField = Root.fieldName(for: subject)
        self.predicateField = Root.fieldName(for: predicate)
        self.objectField = Root.fieldName(for: object)
        self.graphField = Root.fieldName(for: graph)
    }

    public init(
        subject: KeyPath<Root, RDFTerm>,
        predicate: KeyPath<Root, RDFTerm>,
        object: KeyPath<Root, RDFTerm>,
        graph: KeyPath<Root, RDFTerm?>
    ) {
        self.subjectField = Root.fieldName(for: subject)
        self.predicateField = Root.fieldName(for: predicate)
        self.objectField = Root.fieldName(for: object)
        self.graphField = Root.fieldName(for: graph)
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count == 3 || fields.count == 4 else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 4,
                actual: fields.count
            )
        }

        for field in fields.prefix(3)
        where field.type != .rdfTerm || field.isArray {
            throw IndexValidationError.unsupportedField(
                index: identifier,
                field: field,
                reason: "subject, predicate, and object fields must be RDFTerm"
            )
        }

        if fields.count == 4 {
            let graphField = fields[3]
            guard graphField.type == .rdfTerm, !graphField.isArray else {
                throw IndexValidationError.unsupportedField(
                    index: identifier,
                    field: graphField,
                    reason: "graph field must be RDFTerm or Optional<RDFTerm>"
                )
            }
        }
    }
}

extension RDFQuadIndexKind {
    /// Builds the canonical schema value without creating a concrete index
    /// kind instance. Runtime schema boundaries consume this representation.
    public static func canonical(
        subject: KeyPath<Root, RDFTerm>,
        predicate: KeyPath<Root, RDFTerm>,
        object: KeyPath<Root, RDFTerm>,
        graph: KeyPath<Root, RDFTerm>
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
        subject: KeyPath<Root, RDFTerm>,
        predicate: KeyPath<Root, RDFTerm>,
        object: KeyPath<Root, RDFTerm>,
        graph: KeyPath<Root, RDFTerm?>
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
        subject: KeyPath<Root, RDFTerm>,
        predicate: KeyPath<Root, RDFTerm>,
        object: KeyPath<Root, RDFTerm>
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
