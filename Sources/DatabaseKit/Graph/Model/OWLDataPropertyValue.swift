import DatabaseTypes

public protocol OWLDataPropertyValue: Sendable {
    func owlDataPropertyTerms() throws(OWLProjectionError) -> [RDFTerm]
}

extension Optional: OWLDataPropertyValue where Wrapped: OWLDataPropertyValue {
    public func owlDataPropertyTerms()
        throws(OWLProjectionError) -> [RDFTerm] {
        switch self {
        case .none: return []
        case .some(let value): return try value.owlDataPropertyTerms()
        }
    }
}

extension Array: OWLDataPropertyValue where Element: OWLDataPropertyValue {
    public func owlDataPropertyTerms()
        throws(OWLProjectionError) -> [RDFTerm] {
        var terms: [RDFTerm] = []
        for element in self {
            terms.append(contentsOf: try element.owlDataPropertyTerms())
        }
        return terms
    }
}
