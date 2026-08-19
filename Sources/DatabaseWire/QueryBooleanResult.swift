#if DATABASE_KIT_MULTI_BASE
import DatabaseKit

/// A Boolean query result with explicit read consistency and optional
/// Composition provenance.
public struct QueryBooleanResult: WireValue, Sendable {
    public let value: Bool
    public let provenance: CompositionPageProvenance?
    public let consistency: DatabaseReadConsistency

    public init(
        value: Bool,
        provenance: CompositionPageProvenance?,
        consistency: DatabaseReadConsistency
    ) throws(DatabaseWireError) {
        guard provenance == nil || provenance?.originCount == 1 else {
            throw .invalidCompositionProvenance
        }
        self.value = value
        self.provenance = provenance
        self.consistency = consistency
    }

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard provenance == nil || provenance?.originCount == 1 else {
            throw .invalidCompositionProvenance
        }
        writer.writeBool(value)
        writer.writeBool(provenance != nil)
        if let provenance {
            try provenance.encode(into: &writer)
        }
        try consistency.encode(into: &writer)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        try self.init(
            value: reader.readBool(),
            provenance: reader.readBool()
                ? CompositionPageProvenance(from: &reader)
                : nil,
            consistency: DatabaseReadConsistency(from: &reader)
        )
    }
}
#endif
