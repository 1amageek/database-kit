import DatabaseValue

public protocol OWLDataPropertyValue: Sendable {
    func owlDataPropertyTerms() throws -> [DatabaseRDFTerm]
}

extension Optional: OWLDataPropertyValue where Wrapped: OWLDataPropertyValue {
    public func owlDataPropertyTerms() throws -> [DatabaseRDFTerm] {
        switch self {
        case .none: return []
        case .some(let value): return try value.owlDataPropertyTerms()
        }
    }
}

extension Array: OWLDataPropertyValue where Element: OWLDataPropertyValue {
    public func owlDataPropertyTerms() throws -> [DatabaseRDFTerm] {
        try flatMap { try $0.owlDataPropertyTerms() }
    }
}
