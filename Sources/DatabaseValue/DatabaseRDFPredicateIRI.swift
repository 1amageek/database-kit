public struct DatabaseRDFPredicateIRI: Sendable, Hashable, Comparable {
    public let iri: DatabaseRDFIRI

    public init(_ rawValue: String) throws(DatabaseRDFPredicateIRIError) {
        do {
            iri = try DatabaseRDFIRI(rawValue)
        } catch let error {
            throw .invalidIRI(error)
        }
    }

    public init(_ iri: DatabaseRDFIRI) {
        self.iri = iri
    }

    public var rawValue: String { iri.rawValue }

    public var term: DatabaseRDFTerm {
        .iri(rawValue)
    }

    public static func < (
        lhs: DatabaseRDFPredicateIRI,
        rhs: DatabaseRDFPredicateIRI
    ) -> Bool {
        lhs.iri < rhs.iri
    }
}
