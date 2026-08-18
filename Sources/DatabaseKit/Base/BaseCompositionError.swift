#if DATABASE_KIT_MULTIPLE_BASES
public enum BaseCompositionError: Error, Sendable, Equatable {
    case empty
    case duplicateBase(Base.ID)
    case nonCanonicalBaseOrder
    case invalidGeneration
}

#endif
