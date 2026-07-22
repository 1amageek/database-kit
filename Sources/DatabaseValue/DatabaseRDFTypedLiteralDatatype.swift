/// A datatype IRI that can annotate an RDF typed literal directly.
///
/// `rdf:langString` and `rdf:dirLangString` are excluded because RDF 1.2
/// requires their language and direction components to be present.
public struct DatabaseRDFTypedLiteralDatatype: Sendable, Hashable, Comparable,
    CustomStringConvertible
{
    public let iri: DatabaseRDFIRI

    public init(
        _ iri: DatabaseRDFIRI
    ) throws(DatabaseRDFTypedLiteralDatatypeError) {
        guard iri != .rdfLanguageString else {
            throw .languageDatatypeRequiresLanguage
        }
        guard iri != .rdfDirectionalLanguageString else {
            throw .directionalLanguageDatatypeRequiresLanguageAndDirection
        }
        self.iri = iri
    }

    public init(
        _ rawValue: String
    ) throws(DatabaseRDFTypedLiteralDatatypeError) {
        let iri: DatabaseRDFIRI
        do {
            iri = try DatabaseRDFIRI(rawValue)
        } catch let error {
            throw .invalidIRI(error)
        }
        try self.init(iri)
    }

    init(validatedIRI iri: DatabaseRDFIRI) {
        self.iri = iri
    }

    public static let xsdString = Self(validatedIRI: .xsdString)

    public var rawValue: String { iri.rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.iri < rhs.iri
    }

    public var description: String { iri.rawValue }
}
