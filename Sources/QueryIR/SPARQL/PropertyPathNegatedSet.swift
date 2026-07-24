import DatabaseTypes
import DatabaseValue

/// Direction-preserving predicate exclusions for a SPARQL negated property set.
public struct PropertyPathNegatedSet: Sendable, Equatable, Hashable {
    /// A non-nil set enables forward traversal. An empty set matches any forward predicate.
    public let forward: Set<RDFPredicateIRI>?

    /// A non-nil set enables inverse traversal. An empty set matches any inverse predicate.
    public let inverse: Set<RDFPredicateIRI>?

    public init(
        forward: Set<RDFPredicateIRI>? = nil,
        inverse: Set<RDFPredicateIRI>? = nil
    ) throws(PropertyPathNegatedSetError) {
        guard forward != nil || inverse != nil else {
            throw .missingDirection
        }
        self.forward = forward
        self.inverse = inverse
    }

    public var reversed: PropertyPathNegatedSet {
        PropertyPathNegatedSet(
            validatedForward: inverse,
            validatedInverse: forward
        )
    }

    private init(
        validatedForward: Set<RDFPredicateIRI>?,
        validatedInverse: Set<RDFPredicateIRI>?
    ) {
        self.forward = validatedForward
        self.inverse = validatedInverse
    }
}
