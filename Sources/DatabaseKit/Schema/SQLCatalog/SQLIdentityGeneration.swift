/// Whether a user-supplied identity value requires explicit override.
public enum SQLIdentityGeneration: Sendable, Hashable {
    case always
    case byDefault
}
