import DatabaseTypes

/// Declarative metadata for a canonical RDF dataset index.
///
/// Entities remain the source of truth. The execution layer maintains six
/// derived orderings in the same transaction as the entity mutation.
public struct RDFQuadIndexKind<Root: Persistable>: IndexKind {
    public typealias Model = Root

    public static var identifier: String { "rdf_quad" }
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    public let indexFields: [IndexField<Root>]

    public var subjectField: String { indexFields[0].name }
    public var predicateField: String { indexFields[1].name }
    public var objectField: String { indexFields[2].name }
    public var graphField: String? {
        indexFields.count == 4 ? indexFields[3].name : nil
    }

    public var indexName: String {
        let components = fieldNames.map {
            $0.split(separator: ".").joined(separator: "_")
        }
        return ([Root.persistableType, "rdf_quad"] + components)
            .joined(separator: "_")
    }

    public init(
        subject: IndexField<Root>,
        predicate: IndexField<Root>,
        object: IndexField<Root>
    ) {
        self.indexFields = [
            subject,
            predicate,
            object,
        ]
    }

    public init(
        subject: IndexField<Root>,
        predicate: IndexField<Root>,
        object: IndexField<Root>,
        graph: IndexField<Root>
    ) {
        self.indexFields = [
            subject,
            predicate,
            object,
            graph,
        ]
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
