import Core
import DatabaseValue
import DatabaseValueCodable

/// Declares the canonical RDF dataset projection for an OWL-bound record type.
///
/// The record remains the source of truth. The framework materializes one RDF
/// quad for `rdf:type` and one quad for each declared OWL property in the same
/// transaction as the record mutation.
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
    public let graph: DatabaseRDFTerm?

    public var metadata: [String: IndexMetadataValue] {
        var values: [String: IndexMetadataValue] = [
            "individualIRIBase": .string(individualIRIBase)
        ]
        if let graph {
            values["graph"] = .rdfTerm(graph)
        }
        return values
    }

    public init(
        individualIRIBase: String,
        graph: DatabaseRDFTerm? = nil
    ) {
        self.individualIRIBase = individualIRIBase
        self.graph = graph
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.isEmpty else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 0,
                actual: types.count
            )
        }
    }
}
