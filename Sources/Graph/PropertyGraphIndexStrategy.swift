/// Storage strategies that are valid for property-graph entities.
public enum PropertyGraphIndexStrategy: String, Sendable, Codable, CaseIterable {
    case adjacency
    case tripleStore
    case hexastore
    case namedGraphStore

    public var storageStrategy: GraphIndexStrategy {
        switch self {
        case .adjacency: return .adjacency
        case .tripleStore: return .tripleStore
        case .hexastore: return .hexastore
        case .namedGraphStore: return .namedGraphStore
        }
    }
}
