import DatabaseTypes

/// A type-safe reference to a persisted entity.
public struct PersistableReference<Target: Persistable>: Sendable, Hashable {
    public let identity: EntityReference

    public init(
        identity: EntityReference
    ) throws(PersistableReferenceError) {
        guard identity.entity == Target.persistableType else {
            throw .entityMismatch(
                expected: Target.persistableType,
                actual: identity.entity
            )
        }
        do {
            try PersistableIdentifierValidator.validate(
                identity.id,
                as: Target.persistableIdentifierType
            )
        } catch let error {
            throw .invalidIdentifier(
                entity: identity.entity,
                reason: error
            )
        }

        let expectedPartitions = Self.canonicalPartitionNames(
            Target.directoryPathComponents.compactMap { component -> String? in
                guard case .dynamicField(let fieldName) = component else {
                    return nil
                }
                return fieldName
            }
        )
        let actualPartitions = identity.partitions.fields.map(\.key)
        guard Self.haveIdenticalUTF8(
            expectedPartitions,
            actualPartitions
        ) else {
            throw .partitionMismatch(
                entity: identity.entity,
                expected: expectedPartitions,
                actual: actualPartitions
            )
        }
        self.identity = identity
    }

    private static func canonicalPartitionNames(
        _ names: [String]
    ) -> [String] {
        var result: [String] = []
        result.reserveCapacity(names.count)
        for name in names.sorted(by: {
            $0.utf8.lexicographicallyPrecedes($1.utf8)
        }) {
            if let previous = result.last,
               previous.utf8.elementsEqual(name.utf8) {
                continue
            }
            result.append(name)
        }
        return result
    }

    private static func haveIdenticalUTF8(
        _ left: [String],
        _ right: [String]
    ) -> Bool {
        guard left.count == right.count else {
            return false
        }
        for index in left.indices {
            guard left[index].utf8.elementsEqual(right[index].utf8) else {
                return false
            }
        }
        return true
    }
}

extension PersistableReference: PersistableReferenceValue {
    public var persistableIdentity: EntityReference { identity }

    public static func decodePersistedReference(
        _ identity: EntityReference
    ) throws -> Self {
        try Self(identity: identity)
    }
}
