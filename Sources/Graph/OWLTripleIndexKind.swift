// OWLTripleIndexKind.swift
// Graph - IndexKind for materializing @OWLClass entity properties as SPO entries
//
// Pure metadata type (no execution dependency). The IndexKindMaintainable conformance
// and runtime implementation (OWLTripleIndexMaintainer) live in database-framework's
// OntologyIndex module.
//
// This follows the same pattern as GraphIndexKind:
//   database-kit:       GraphIndexKind (metadata)
//   database-framework: GraphIndexKind+Maintainable (runtime bridge)

import Foundation
import Core

/// IndexKind that materializes @OWLClass entity properties as SPO triple entries.
///
/// When an entity with this index is saved, the OntologyIndex module's maintainer:
/// 1. Generates `rdf:type` triple from `ontologyClassIRI`
/// 2. Generates triples for all `@OWLDataProperty` fields via `ontologyPropertyDescriptors`
/// 3. Writes SPO/POS/OSP index entries for SPARQL queryability
///
/// **Auto-generated**: The `@OWLClass` macro automatically adds this IndexKind
/// to the entity's `descriptors`. No manual `#Index` declaration needed.
///
/// ```swift
/// @Persistable
/// @OWLClass("ex:Person")
/// struct Person {
///     @OWLDataProperty("rdfs:label") var name: String
///     @OWLDataProperty("ex:email") var email: String
/// }
/// // @Persistable auto-generates:
/// //   IndexDescriptor(name: "Person_owlTriple",
/// //                   keyPaths: [],
/// //                   kind: OWLTripleIndexKind<Person>())
/// ```
public struct OWLTripleIndexKind<Root: Persistable>: IndexKind, Sendable, Codable, Hashable {

    // MARK: - IndexKind Requirements

    public static var identifier: String { "owlTriple" }

    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    public var indexName: String {
        "\(Root.persistableType)_owlTriple"
    }

    public var fieldNames: [String] { [] }

    public static func validateTypes(_ types: [Any.Type]) throws {}

    // MARK: - Properties

    /// Named graph IRI for the materialized triples.
    public let graph: String

    /// IRI prefix for entity IRI generation.
    ///
    /// Entity IRI format: `{prefix}:{lowercased_type_name}/{id}`
    public let prefix: String

    // MARK: - Initialization

    public init(graph: String = "default", prefix: String = "entity") {
        self.graph = graph
        self.prefix = prefix
    }
}
