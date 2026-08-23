
import DatabaseTypes

/// Feature-specific access path layered on top of a logical row source.
///
/// `DataSource` stays relational/graph-oriented. Optional index- or
/// fusion-based access is represented here to preserve `QueryIR` extensibility.
public enum AccessPath: Sendable, Equatable, Hashable {
    case index(IndexScanSource)
    case fusion(FusionSource)
}
