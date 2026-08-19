#if DATABASE_KIT_MULTI_BASE
import DatabaseTypes

/// The unambiguous address of an entity whose model identity is local to a Base.
public struct EntityAddress: Sendable, Hashable, Comparable {
    public let baseID: Base.ID
    public let entity: EntityReference

    public init(baseID: Base.ID, entity: EntityReference) {
        self.baseID = baseID
        self.entity = entity
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.baseID != rhs.baseID {
            return lhs.baseID < rhs.baseID
        }
        return lhs.entity < rhs.entity
    }
}

#endif
