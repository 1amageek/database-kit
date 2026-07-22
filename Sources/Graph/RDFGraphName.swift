import DatabaseValue
import DatabaseValueCodable

/// A validated RDF named-graph identifier.
///
/// The RDF default graph has no name and is therefore represented elsewhere
/// by `nil`. This value can only contain an absolute IRI or a non-empty blank
/// node identifier.
public struct RDFGraphName: Sendable, Hashable, Codable, Comparable {
    public let term: DatabaseRDFTerm

    public init(_ term: DatabaseRDFTerm) throws {
        switch term {
        case .iri(let value):
            guard DatabaseRDFIRIValidator.isAbsolute(value) else {
                throw RDFDatasetValidationError.invalidIRI(value)
            }
        case .blankNode(let identifier):
            guard !identifier.isEmpty else {
                throw RDFDatasetValidationError.invalidBlankNodeIdentifier(
                    identifier
                )
            }
        case .literal, .tripleTerm:
            throw RDFDatasetValidationError.invalidGraphName(term)
        }
        self.term = term
    }

    public init(iri: String) throws {
        try self.init(.iri(iri))
    }

    public init(blankNodeIdentifier: String) throws {
        try self.init(.blankNode(blankNodeIdentifier))
    }

    public init(from decoder: any Decoder) throws {
        try self.init(DatabaseRDFTerm(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        try term.encode(to: encoder)
    }

    public static func < (lhs: RDFGraphName, rhs: RDFGraphName) -> Bool {
        lhs.term < rhs.term
    }
}
