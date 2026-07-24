import DatabaseTypes
import Core
import DatabaseValue
import DatabaseValueCodable

/// Declares the canonical RDF dataset projection for an OWL-bound persistable type.
///
/// The entity remains the source of truth. The framework materializes one RDF
/// quad for `rdf:type` and one quad for each declared OWL property in the same
/// transaction as the entity mutation.
public struct OWLClassRDFIndexKind<Root: OWLClassEntity>: IndexKind, Sendable, Codable, Hashable {
    public static var identifier: String { "owl_class_rdf" }
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    public var indexName: String {
        "\(Root.persistableType)_owl_rdf"
    }

    public var fieldNames: [String] { [] }

    /// Base IRI used to identify materialized individuals.
    ///
    /// The final IRI appends the percent-encoded persistable type and identifier.
    public let individualIRIBase: String

    /// Fixed graph for the projection. `nil` writes to the default graph.
    public let graph: RDFGraphName?

    public var metadata: [String: FieldValue] {
        var values: [String: FieldValue] = [
            "individualIRIBase": .string(individualIRIBase)
        ]
        if let graph {
            values["graph"] = .rdfTerm(graph.term)
        }
        return values
    }

    public init(
        individualIRIBase: String,
        graph: RDFGraphName? = nil
    ) {
        self.individualIRIBase = individualIRIBase
        self.graph = graph
    }

    public func validateConfiguration() throws(IndexTypeValidationError) {
        guard !individualIRIBase.isEmpty else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "Individual IRI base must not be empty"
            )
        }
    }

    public static func validateTypes(
        _ types: [Any.Type]
    ) throws(IndexTypeValidationError) {
        guard types.isEmpty else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 0,
                actual: types.count
            )
        }
    }
}
