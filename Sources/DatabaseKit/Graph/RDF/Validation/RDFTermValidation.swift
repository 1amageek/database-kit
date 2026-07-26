import DatabaseTypes

public enum RDFTermValidation {
    public static func validate(
        _ term: RDFTerm,
        role: RDFTermRole = .term,
        limits: RDFTermValidationLimits = .default
    ) throws(RDFTermValidationError) {
        let kind = term.rdfTermKind
        guard kind.isValid(for: role) else {
            throw .invalidRole(expected: role, actual: kind)
        }

        var pending: [(term: RDFTerm, depth: Int)] = [(term, 0)]
        var termCount = 0
        while let current = pending.popLast() {
            guard current.depth <= limits.maximumDepth else {
                throw .maximumDepthExceeded(
                    actual: current.depth,
                    maximum: limits.maximumDepth
                )
            }
            let (nextTermCount, overflow) = termCount.addingReportingOverflow(1)
            guard !overflow else {
                throw .termCountOverflow
            }
            guard nextTermCount <= limits.maximumTermCount else {
                throw .maximumTermCountExceeded(
                    actual: nextTermCount,
                    maximum: limits.maximumTermCount
                )
            }
            termCount = nextTermCount

            guard case .tripleTerm(
                let subject,
                let predicate,
                let object
            ) = current.term else {
                continue
            }
            let (nestedDepth, depthOverflow) = current.depth
                .addingReportingOverflow(1)
            guard !depthOverflow else {
                throw .termCountOverflow
            }
            pending.append((object, nestedDepth))
            pending.append((predicate.term, nestedDepth))
            pending.append((subject.term, nestedDepth))
        }
    }
}

extension RDFTermKind {
    package func isValid(for role: RDFTermRole) -> Bool {
        switch role {
        case .term, .object:
            true
        case .subject, .graphName:
            self == .iri || self == .blankNode
        case .predicate:
            self == .iri
        }
    }
}

extension RDFTerm {
    package var rdfTermKind: RDFTermKind {
        switch self {
        case .blankNode:
            .blankNode
        case .iri:
            .iri
        case .literal:
            .literal
        case .tripleTerm:
            .tripleTerm
        }
    }
}
