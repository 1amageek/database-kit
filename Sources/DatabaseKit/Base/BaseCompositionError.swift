#if DATABASE_KIT_MULTI_BASE
public enum BaseCompositionError: Error, Sendable, Equatable {
    case empty
    case duplicateBase(Base.ID)
    case nonCanonicalBaseOrder
    case invalidGeneration
}

#endif
