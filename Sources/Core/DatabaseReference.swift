import DatabaseValue
import DatabaseValueCodable

/// A type-safe reference to a persisted entity.
public struct DatabaseReference<Target: Persistable>: Sendable, Hashable, Codable {
    public let identity: PersistableIdentity

    public init(
        identity: PersistableIdentity
    ) throws(DatabaseReferenceError) {
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

        var partitionNumbers = Set<UInt32>()
        var partitionNames = Set<String>()
        for partition in identity.partitions {
            guard partition.number > 0 else {
                throw .invalidPartitionFieldNumber(
                    entity: identity.entity,
                    field: partition.name
                )
            }
            guard partitionNumbers.insert(partition.number).inserted else {
                throw .duplicatePartitionFieldNumber(
                    entity: identity.entity,
                    number: partition.number
                )
            }
            guard partitionNames.insert(partition.name).inserted else {
                throw .duplicatePartitionFieldName(
                    entity: identity.entity,
                    field: partition.name
                )
            }
        }
        self.identity = identity
    }
}

extension DatabaseReference: PersistableReferenceValue {
    public var persistableIdentity: PersistableIdentity { identity }

    public static func decodePersistedReference(
        _ identity: PersistableIdentity
    ) throws -> Self {
        try Self(identity: identity)
    }
}
