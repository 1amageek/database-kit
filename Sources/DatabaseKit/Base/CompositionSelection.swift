#if DATABASE_KIT_MULTI_BASE
/// Selects either a durable named Composition or a request-scoped canonical
/// set of Bases. A derived selection carries no synthetic catalog identity.
public struct CompositionSelection: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case named
        case derived
    }

    public let kind: Kind
    public let namedID: Base.Composition.ID?
    public let bases: [Base.ID]?

    private init(
        kind: Kind,
        namedID: Base.Composition.ID?,
        bases: [Base.ID]?
    ) {
        self.kind = kind
        self.namedID = namedID
        self.bases = bases
    }

    public static func named(
        _ id: Base.Composition.ID
    ) -> CompositionSelection {
        CompositionSelection(kind: .named, namedID: id, bases: nil)
    }

    public static func derived(
        _ bases: [Base.ID]
    ) throws(BaseCompositionError) -> CompositionSelection {
        CompositionSelection(
            kind: .derived,
            namedID: nil,
            bases: try canonicalBases(bases)
        )
    }

    private static func canonicalBases(
        _ bases: [Base.ID]
    ) throws(BaseCompositionError) -> [Base.ID] {
        guard !bases.isEmpty else { throw .empty }
        let canonical = bases.sorted()
        for (previous, current) in zip(canonical, canonical.dropFirst()) {
            guard previous != current else { throw .duplicateBase(current) }
        }
        return canonical
    }
}
#endif
