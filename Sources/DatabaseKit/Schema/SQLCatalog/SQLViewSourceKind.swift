/// The disjoint identity domain of a durable view source dependency.
public enum SQLViewSourceKind: Sendable, Hashable {
    case catalog
    case informationSchema
}
