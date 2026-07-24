import DatabaseTypes

public protocol OWLDataPropertyValue: Sendable {
    func owlDataPropertyTerms() throws -> [RDFTerm]
}

extension Optional: OWLDataPropertyValue where Wrapped: OWLDataPropertyValue {
    public func owlDataPropertyTerms() throws -> [RDFTerm] {
        switch self {
        case .none: return []
        case .some(let value): return try value.owlDataPropertyTerms()
        }
    }
}

extension Array: OWLDataPropertyValue where Element: OWLDataPropertyValue {
    public func owlDataPropertyTerms() throws -> [RDFTerm] {
        try flatMap { try $0.owlDataPropertyTerms() }
    }
}
