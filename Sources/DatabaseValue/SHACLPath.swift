import DatabaseTypes

/// A well-formed SHACL property path.
public indirect enum SHACLPath: Sendable, Hashable {
    case predicate(RDFPredicateIRI)
    case inverse(SHACLPath)
    case sequence(SHACLPathList)
    case alternative(SHACLPathList)
    case zeroOrMore(SHACLPath)
    case oneOrMore(SHACLPath)
    case zeroOrOne(SHACLPath)
}

/// The list value used by SHACL sequence and alternative paths.
///
/// Both SHACL path forms require at least two members.
public struct SHACLPathList: Sendable, Hashable {
    public let elements: [SHACLPath]

    public init(
        _ elements: consuming [SHACLPath]
    ) throws(SHACLPathError) {
        guard elements.count >= 2 else {
            throw .insufficientMembers(actual: elements.count)
        }
        self.elements = consume elements
    }
}

public enum SHACLPathError: Error, Sendable, Equatable {
    case insufficientMembers(actual: Int)
}

extension SHACLPath {
    public var isPredicatePath: Bool {
        if case .predicate = self { return true }
        return false
    }

    public var predicateIRI: RDFPredicateIRI? {
        guard case .predicate(let iri) = self else { return nil }
        return iri
    }

    public var referencedPredicates: Set<RDFPredicateIRI> {
        var predicates: Set<RDFPredicateIRI> = []
        var pending: [SHACLPath] = [self]
        while let path = pending.popLast() {
            switch path {
            case .predicate(let iri):
                predicates.insert(iri)
            case .inverse(let inner),
                 .zeroOrMore(let inner),
                 .oneOrMore(let inner),
                 .zeroOrOne(let inner):
                pending.append(inner)
            case .sequence(let paths), .alternative(let paths):
                pending.append(contentsOf: paths.elements)
            }
        }
        return predicates
    }
}

extension SHACLPath: CustomStringConvertible {
    public var description: String {
        switch self {
        case .predicate(let iri):
            return iri.rawValue
        case .inverse(let inner):
            return "^(\(inner))"
        case .sequence(let paths):
            return paths.elements.map { $0.description }.joined(separator: " / ")
        case .alternative(let paths):
            return paths.elements.map { $0.description }.joined(separator: " | ")
        case .zeroOrMore(let inner):
            return "(\(inner))*"
        case .oneOrMore(let inner):
            return "(\(inner))+"
        case .zeroOrOne(let inner):
            return "(\(inner))?"
        }
    }
}
