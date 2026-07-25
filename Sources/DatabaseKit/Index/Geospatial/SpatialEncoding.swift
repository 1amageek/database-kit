/// Space-filling curve used to order geographic values.
public enum SpatialEncoding: String, Sendable, Hashable {
    case s2
    case morton
}
