/// A resolved absolute RDF IRI validated against the RFC 3987 grammar.
///
/// RDF identity is exact Unicode code-point identity. The original spelling
/// is therefore retained without Unicode, scheme, host, or percent-triplet
/// normalization.
public struct DatabaseRDFIRI: Sendable, Hashable, Comparable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(_ rawValue: String) throws(DatabaseRDFIRIError) {
        try DatabaseRDFIRIParser.validate(rawValue)
        self.rawValue = rawValue
    }

    init(validatedRawValue rawValue: String) {
        self.rawValue = rawValue
    }

    public static let xsdString = Self(
        validatedRawValue: "http://www.w3.org/2001/XMLSchema#string"
    )

    public static let rdfLanguageString = Self(
        validatedRawValue:
            "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString"
    )

    public static let rdfDirectionalLanguageString = Self(
        validatedRawValue:
            "http://www.w3.org/1999/02/22-rdf-syntax-ns#dirLangString"
    )

    public static func == (lhs: Self, rhs: Self) -> Bool {
        DatabaseStringIdentity.equal(lhs.rawValue, rhs.rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        DatabaseStringIdentity.less(lhs.rawValue, rhs.rawValue)
    }

    public func hash(into hasher: inout Hasher) {
        DatabaseStringIdentity.hash(rawValue, into: &hasher)
    }

    public var description: String { rawValue }
}
