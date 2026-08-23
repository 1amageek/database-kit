/// Direction used by a property-graph Fusion traversal.
public enum FusionConnectedDirection: UInt8, Sendable, Equatable, Hashable {
    case outgoing
    case incoming
    case both
}
