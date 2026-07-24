/// The storage cardinality of a typed relationship field.
public enum RelationshipCardinality: String, Sendable, Hashable {
    case requiredToOne
    case optionalToOne
    case toMany
}
