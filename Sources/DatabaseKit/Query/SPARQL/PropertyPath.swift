import DatabaseTypes

/// PropertyPath.swift
/// SPARQL 1.1/1.2 Property Path types
///
/// Reference:
/// - W3C SPARQL 1.1 Property Paths
/// - W3C SPARQL 1.2 (Draft) - Extended Property Paths

public indirect enum PropertyPath: Sendable, Equatable, Hashable {
    case iri(RDFPredicateIRI)
    case inverse(PropertyPath)
    case sequence(PropertyPath, PropertyPath)
    case alternative(PropertyPath, PropertyPath)
    case zeroOrMore(PropertyPath)
    case oneOrMore(PropertyPath)
    case zeroOrOne(PropertyPath)
    case negatedPropertySet(PropertyPathNegatedSet)
    case range(PropertyPath, PropertyPathRange)
}

// MARK: - PropertyPath Builders

extension PropertyPath {
    /// Create a simple IRI path
    public static func uri(_ iri: RDFPredicateIRI) -> PropertyPath {
        .iri(iri)
    }

    /// Create an inverse path: ^path
    public static func inv(_ path: PropertyPath) -> PropertyPath {
        .inverse(path)
    }

    /// Create a sequence path: path1 / path2
    /// - Parameters:
    ///   - first: The first path in the sequence.
    ///   - remaining: Additional paths in their evaluation order.
    public static func seq(
        _ first: PropertyPath,
        _ remaining: PropertyPath...
    ) -> PropertyPath {
        remaining.reduce(first) { .sequence($0, $1) }
    }

    /// Create an alternative path: path1 | path2
    /// - Parameters:
    ///   - first: The first path in the alternative.
    ///   - remaining: Additional alternative paths.
    public static func alt(
        _ first: PropertyPath,
        _ remaining: PropertyPath...
    ) -> PropertyPath {
        remaining.reduce(first) { .alternative($0, $1) }
    }

    /// Create a zero-or-more path: path*
    public static func star(_ path: PropertyPath) -> PropertyPath {
        .zeroOrMore(path)
    }

    /// Create a one-or-more path: path+
    public static func plus(_ path: PropertyPath) -> PropertyPath {
        .oneOrMore(path)
    }

    /// Create a zero-or-one path: path?
    public static func opt(_ path: PropertyPath) -> PropertyPath {
        .zeroOrOne(path)
    }

    /// Create a negation path: !path
    public static func negated(
        _ exclusions: PropertyPathNegatedSet
    ) -> PropertyPath {
        .negatedPropertySet(exclusions)
    }

    /// Create a ranged path: path{min,max}
    public static func ranged(
        _ path: PropertyPath,
        bounds: PropertyPathRange
    ) -> PropertyPath {
        .range(path, bounds)
    }
}

// MARK: - PropertyPath Analysis

extension PropertyPath {
    /// Returns all IRIs used in this path
    public var iris: Set<RDFPredicateIRI> {
        var result = Set<RDFPredicateIRI>()
        collectIRIs(into: &result)
        return result
    }

    private func collectIRIs(
        into result: inout Set<RDFPredicateIRI>
    ) {
        switch self {
        case .iri(let iri):
            result.insert(iri)
        case .inverse(let path):
            path.collectIRIs(into: &result)
        case .sequence(let left, let right):
            left.collectIRIs(into: &result)
            right.collectIRIs(into: &result)
        case .alternative(let left, let right):
            left.collectIRIs(into: &result)
            right.collectIRIs(into: &result)
        case .zeroOrMore(let path), .oneOrMore(let path), .zeroOrOne(let path):
            path.collectIRIs(into: &result)
        case .negatedPropertySet(let exclusions):
            result.formUnion(exclusions.forward ?? [])
            result.formUnion(exclusions.inverse ?? [])
        case .range(let path, _):
            path.collectIRIs(into: &result)
        }
    }

    /// Returns true if this path contains any repetition operators (*, +, ?)
    public var hasRepetition: Bool {
        switch self {
        case .iri, .negatedPropertySet:
            return false
        case .inverse(let path):
            return path.hasRepetition
        case .sequence(let left, let right), .alternative(let left, let right):
            return left.hasRepetition || right.hasRepetition
        case .zeroOrMore, .oneOrMore, .zeroOrOne, .range:
            return true
        }
    }

    /// Returns true if this path can match zero-length paths
    public var canMatchEmpty: Bool {
        switch self {
        case .iri, .negatedPropertySet, .oneOrMore:
            return false
        case .inverse(let path):
            return path.canMatchEmpty
        case .sequence(let left, let right):
            return left.canMatchEmpty && right.canMatchEmpty
        case .alternative(let left, let right):
            return left.canMatchEmpty || right.canMatchEmpty
        case .zeroOrMore, .zeroOrOne:
            return true
        case .range(let path, let bounds):
            return bounds.minimum == 0 || path.canMatchEmpty
        }
    }

    /// Returns the minimum path length
    public var minLength: Int {
        switch self {
        case .iri:
            return 1
        case .inverse(let path):
            return path.minLength
        case .sequence(let left, let right):
            return left.minLength + right.minLength
        case .alternative(let left, let right):
            return min(left.minLength, right.minLength)
        case .zeroOrMore, .zeroOrOne:
            return 0
        case .oneOrMore(let path):
            return path.minLength
        case .negatedPropertySet:
            return 1
        case .range(let path, let bounds):
            return path.minLength * bounds.minimum
        }
    }

    /// Returns the maximum path length (nil if unbounded)
    public var maxLength: Int? {
        switch self {
        case .iri, .negatedPropertySet:
            return 1
        case .inverse(let path):
            return path.maxLength
        case .sequence(let left, let right):
            guard let l = left.maxLength, let r = right.maxLength else { return nil }
            return l + r
        case .alternative(let left, let right):
            guard let l = left.maxLength, let r = right.maxLength else { return nil }
            return max(l, r)
        case .zeroOrMore, .oneOrMore:
            return nil
        case .zeroOrOne(let path):
            return path.maxLength
        case .range(let path, let bounds):
            guard let pathMax = path.maxLength,
                  let m = bounds.maximum else { return nil }
            return pathMax * m
        }
    }

    /// Returns true if this path is unbounded
    public var isUnbounded: Bool {
        maxLength == nil
    }

}

// MARK: - PropertyPath Transformations

extension PropertyPath {
    /// Reverse the path direction
    public func reversed() -> PropertyPath {
        switch self {
        case .iri(let iri):
            return .inverse(.iri(iri))
        case .inverse(let path):
            return path  // Double inverse cancels out
        case .sequence(let left, let right):
            return .sequence(right.reversed(), left.reversed())
        case .alternative(let left, let right):
            return .alternative(left.reversed(), right.reversed())
        case .zeroOrMore(let path):
            return .zeroOrMore(path.reversed())
        case .oneOrMore(let path):
            return .oneOrMore(path.reversed())
        case .zeroOrOne(let path):
            return .zeroOrOne(path.reversed())
        case .negatedPropertySet(let exclusions):
            return .negatedPropertySet(exclusions.reversed)
        case .range(let path, let bounds):
            return .range(path.reversed(), bounds)
        }
    }

    /// Simplify the path expression
    public func simplified() -> PropertyPath {
        switch self {
        case .iri, .negatedPropertySet:
            return self

        case .inverse(let path):
            let simplified = path.simplified()
            // Double inverse cancels out
            if case .inverse(let inner) = simplified {
                return inner
            }
            return .inverse(simplified)

        case .sequence(let left, let right):
            let l = left.simplified()
            let r = right.simplified()
            // Flatten nested sequences
            return .sequence(l, r)

        case .alternative(let left, let right):
            let l = left.simplified()
            let r = right.simplified()
            return .alternative(l, r)

        case .zeroOrMore(let path):
            let simplified = path.simplified()
            // (a*)* = a*
            if case .zeroOrMore = simplified {
                return simplified
            }
            // (a+)* = a*
            if case .oneOrMore(let inner) = simplified {
                return .zeroOrMore(inner)
            }
            return .zeroOrMore(simplified)

        case .oneOrMore(let path):
            let simplified = path.simplified()
            // (a+)+ = a+
            if case .oneOrMore = simplified {
                return simplified
            }
            // (a*)+ = a*
            if case .zeroOrMore = simplified {
                return simplified
            }
            return .oneOrMore(simplified)

        case .zeroOrOne(let path):
            let simplified = path.simplified()
            // (a?)? = a?
            if case .zeroOrOne = simplified {
                return simplified
            }
            return .zeroOrOne(simplified)

        case .range(let path, let bounds):
            let simplified = path.simplified()
            // {1,1} = plain path
            if bounds.minimum == 1 && bounds.maximum == 1 {
                return simplified
            }
            // {0,1} = ?
            if bounds.minimum == 0 && bounds.maximum == 1 {
                return .zeroOrOne(simplified)
            }
            // {1,} = +
            if bounds.minimum == 1 && bounds.maximum == nil {
                return .oneOrMore(simplified)
            }
            // {0,} = *
            if bounds.minimum == 0 && bounds.maximum == nil {
                return .zeroOrMore(simplified)
            }
            return .range(simplified, bounds)
        }
    }
}

// MARK: - SPARQL Serialization

extension PropertyPath {
    /// Generate SPARQL property path syntax
    public func toSPARQL(prefixes: [String: String] = [:]) -> String {
        switch self {
        case .iri(let iri):
            // Try to use prefix
            for (prefix, base) in prefixes {
                if iri.rawValue.hasPrefix(base) {
                    let local = String(iri.rawValue.dropFirst(base.count))
                    return "\(prefix):\(local)"
                }
            }
            return "<\(iri.rawValue)>"

        case .inverse(let path):
            return "^\(path.toSPARQL(prefixes: prefixes))"

        case .sequence(let left, let right):
            return "\(left.toSPARQL(prefixes: prefixes))/\(right.toSPARQL(prefixes: prefixes))"

        case .alternative(let left, let right):
            return "(\(left.toSPARQL(prefixes: prefixes))|\(right.toSPARQL(prefixes: prefixes)))"

        case .zeroOrMore(let path):
            return "\(wrapIfComplex(path, prefixes: prefixes))*"

        case .oneOrMore(let path):
            return "\(wrapIfComplex(path, prefixes: prefixes))+"

        case .zeroOrOne(let path):
            return "\(wrapIfComplex(path, prefixes: prefixes))?"

        case .negatedPropertySet(let exclusions):
            var values = (exclusions.forward ?? []).sorted().map {
                formatIRI($0, prefixes: prefixes)
            }
            values.append(contentsOf: (exclusions.inverse ?? []).sorted().map {
                "^\(formatIRI($0, prefixes: prefixes))"
            })
            if values.count == 1 {
                return "!\(values[0])"
            }
            return "!(\(values.joined(separator: "|")))"

        case .range(let path, let bounds):
            let pathStr = wrapIfComplex(path, prefixes: prefixes)
            let minStr = String(bounds.minimum)
            let maxStr = bounds.maximum.map(String.init) ?? ""
            return "\(pathStr){\(minStr),\(maxStr)}"
        }
    }

    private func wrapIfComplex(_ path: PropertyPath, prefixes: [String: String]) -> String {
        switch path {
        case .iri, .inverse, .negatedPropertySet:
            return path.toSPARQL(prefixes: prefixes)
        default:
            return "(\(path.toSPARQL(prefixes: prefixes)))"
        }
    }

    private func formatIRI(
        _ iri: RDFPredicateIRI,
        prefixes: [String: String]
    ) -> String {
        for (prefix, base) in prefixes {
            if iri.rawValue.hasPrefix(base) {
                let local = String(iri.rawValue.dropFirst(base.count))
                return "\(prefix):\(local)"
            }
        }
        return "<\(iri.rawValue)>"
    }
}
