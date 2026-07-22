/// A reference to a bound query parameter.
public enum QueryParameterReference: Sendable, Equatable, Hashable {
    /// A one-based positional parameter.
    case position(UInt32)

    /// A named parameter without its SQL prefix.
    case name(String)
}
