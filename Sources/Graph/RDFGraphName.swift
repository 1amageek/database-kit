import DatabaseValue
import DatabaseValueCodable
import DatabaseTypes

/// A validated RDF named-graph identifier.
///
/// The RDF default graph has no name and is therefore represented elsewhere
/// by `nil`. This value can only contain an absolute IRI or a non-empty blank
/// node identifier.
public struct RDFGraphName: Sendable, Hashable, Codable, Comparable {
    public let term: RDFTerm

    public init(_ term: RDFTerm) throws {
        switch term {
        case .iri, .blankNode:
            break
        case .literal, .tripleTerm:
            throw RDFDatasetValidationError.invalidGraphName(term)
        }
        self.term = term
    }

    public init(iri: String) throws {
        try self.init(.iri(try RDFIRI(iri)))
    }

    public init(blankNodeIdentifier: String) throws {
        try self.init(
            .blankNode(try RDFBlankNodeIdentifier(blankNodeIdentifier))
        )
    }

    public init(from decoder: any Decoder) throws {
        try self.init(RDFTerm(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        try term.encode(to: encoder)
    }

    public static func < (lhs: RDFGraphName, rhs: RDFGraphName) -> Bool {
        lhs.term < rhs.term
    }
}
