#if DATABASE_KIT_MULTI_BASE
/// Immutable Composition identity and member set fixed for one execution.
/// Derived Compositions deliberately have neither an ID nor a generation.
public struct CompositionResolution: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case named
        case derived
    }

    public let kind: Kind
    public let namedID: Base.Composition.ID?
    public let generation: UInt64?
    public let bases: [Base.ID]

    private init(
        kind: Kind,
        namedID: Base.Composition.ID?,
        generation: UInt64?,
        bases: [Base.ID]
    ) {
        self.kind = kind
        self.namedID = namedID
        self.generation = generation
        self.bases = bases
    }

    public static func named(
        id: Base.Composition.ID,
        generation: UInt64,
        bases: [Base.ID]
    ) throws(BaseCompositionError) -> CompositionResolution {
        guard generation > 0 else { throw .invalidGeneration }
        return CompositionResolution(
            kind: .named,
            namedID: id,
            generation: generation,
            bases: try canonicalBases(bases)
        )
    }

    public static func derived(
        _ bases: [Base.ID]
    ) throws(BaseCompositionError) -> CompositionResolution {
        CompositionResolution(
            kind: .derived,
            namedID: nil,
            generation: nil,
            bases: try canonicalBases(bases)
        )
    }

    private static func canonicalBases(
        _ bases: [Base.ID]
    ) throws(BaseCompositionError) -> [Base.ID] {
        guard !bases.isEmpty else { throw .empty }
        for (previous, current) in zip(bases, bases.dropFirst()) {
            guard previous < current else {
                if previous == current { throw .duplicateBase(current) }
                throw .nonCanonicalBaseOrder
            }
        }
        return bases
    }
}
#endif
