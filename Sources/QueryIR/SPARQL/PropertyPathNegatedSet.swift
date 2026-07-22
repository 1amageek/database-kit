import DatabaseValue

/// Direction-preserving predicate exclusions for a SPARQL negated property set.
public struct PropertyPathNegatedSet: Sendable, Equatable, Hashable {
    /// A non-nil set enables forward traversal. An empty set matches any forward predicate.
    public let forward: Set<DatabaseRDFPredicateIRI>?

    /// A non-nil set enables inverse traversal. An empty set matches any inverse predicate.
    public let inverse: Set<DatabaseRDFPredicateIRI>?

    public init(
        forward: Set<DatabaseRDFPredicateIRI>? = nil,
        inverse: Set<DatabaseRDFPredicateIRI>? = nil
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
        validatedForward: Set<DatabaseRDFPredicateIRI>?,
        validatedInverse: Set<DatabaseRDFPredicateIRI>?
    ) {
        self.forward = validatedForward
        self.inverse = validatedInverse
    }
}
