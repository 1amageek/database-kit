import DatabaseValue
import DatabaseValueCodable

/// A type-safe reference to a persisted record.
public struct DatabaseReference<Target: Persistable>: Sendable, Hashable, Codable {
    public let identity: RecordIdentity

    public init(
        identity: RecordIdentity
    ) throws(DatabaseReferenceError) {
        guard identity.entity == Target.persistableType else {
            throw .entityMismatch(
                expected: Target.persistableType,
                actual: identity.entity
            )
        }
        do {
            try RecordIdentifierValidator.validate(
                identity.id,
                as: Target.recordIdentifierType
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

extension DatabaseReference: DatabaseRecordReferenceValue {
    public var recordIdentity: RecordIdentity { identity }

    public static func decodeDatabaseRecordReference(
        _ identity: RecordIdentity
    ) throws -> Self {
        try Self(identity: identity)
    }
}
