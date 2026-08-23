/// Schema-authoritative index selection for a Fusion input.
public enum FusionIndexSelection: Sendable, Equatable, Hashable {
    case named(name: String, type: IndexType)
    case matching(
        type: IndexType,
        fields: [FieldIdentity],
        fieldMatch: FusionIndexFieldMatch
    )
}
