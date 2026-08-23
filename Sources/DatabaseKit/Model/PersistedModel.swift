import DatabaseTypes

/// An owned, storage-independent snapshot of one compiled model.
///
/// A `PersistedModel` is produced once when a concrete Swift model crosses into
/// heterogeneous database execution. Query, index, and mutation runtimes can
/// then consume the canonical `FieldValue` representation without reopening the
/// concrete `Persistable` type or rebuilding the fields through JSON.
public struct PersistedModel: PersistedEntityValue, Hashable {
    public let entity: String
    public let fields: [PersistableField]

    public init(
        entity: String,
        fields: consuming [PersistableField]
    ) throws(PersistedModelError) {
        guard !entity.isEmpty else {
            throw .emptyEntity
        }

        var names = Set<String>()
        var numbers = Set<UInt32>()
        names.reserveCapacity(fields.count)
        numbers.reserveCapacity(fields.count)
        for index in fields.indices {
            let field = fields[index]
            guard names.insert(field.name).inserted else {
                throw .duplicateFieldName(field.name)
            }
            guard numbers.insert(field.number).inserted else {
                throw .duplicateFieldNumber(field.number)
            }
        }

        self.entity = entity
        self.fields = fields
    }

    public init<Model: Persistable>(
        _ model: borrowing Model
    ) throws {
        self = try PersistedModel(
            entity: Model.persistableType,
            fields: PersistableFieldEncoder.encode(model)
        )
    }

    public func value(forFieldNamed name: String) -> FieldValue? {
        fields.first { $0.name == name }?.value
    }

    public func value(for identity: FieldIdentity) -> FieldValue? {
        fields.first {
            $0.number == identity.number && $0.name == identity.name
        }?.value
    }

    public var persistedEntityName: String { entity }

    public func persistedValue(
        forFieldNamed name: String
    ) throws(PersistableEncodingError) -> FieldValue? {
        value(forFieldNamed: name)
    }

    public func persistedFields() -> [PersistableField] {
        fields
    }

    public func decode<Model: Persistable>(
        as type: Model.Type
    ) throws -> Model {
        guard entity == type.persistableType else {
            throw PersistedModelError.entityMismatch(
                expected: type.persistableType,
                actual: entity
            )
        }
        return try type.decodePersistedFields(fields)
    }

    /// Materializes byte and vector views into self-contained field owners.
    /// Use this when the model must outlive the frame or storage value from
    /// which its canonical fields were decoded.
    public func detached() -> PersistedModel {
        PersistedModel(
            validatedEntity: entity,
            fields: fields.map { field in
                PersistableField(
                    validatedNumber: field.number,
                    validatedName: field.name,
                    value: PersistedFieldValueOwnership.detached(field.value)
                )
            }
        )
    }

    private init(
        validatedEntity entity: String,
        fields: consuming [PersistableField]
    ) {
        self.entity = entity
        self.fields = fields
    }
}
