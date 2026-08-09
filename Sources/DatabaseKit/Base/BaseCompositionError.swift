public enum BaseCompositionError: Error, Sendable, Equatable {
    case empty
    case duplicateBase(Base.ID)
    case nonCanonicalBaseOrder
}
