#if DATABASE_KIT_MULTIPLE_BASES
/// The complete Base lineage of one value returned by a Composition.
public enum CompositionOrigin: Sendable, Hashable {
    case source(Base.ID)
    case derived(contributors: [Base.ID])
}

#endif
