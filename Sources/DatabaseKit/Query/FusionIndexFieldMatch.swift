/// Field-matching policy used when a Fusion input selects an index by schema.
public enum FusionIndexFieldMatch: UInt8, Sendable, Equatable, Hashable {
    case exact
    case contains
}
