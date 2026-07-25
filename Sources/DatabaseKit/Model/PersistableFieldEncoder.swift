import DatabaseTypes

/// Entry points used by macro-generated, statically typed persistence code.
public enum PersistableFieldEncoder {
    public static func encode<Model: Persistable>(
        _ model: borrowing Model
    ) throws(PersistableEncodingError) -> [PersistableField] {
        var output = PersistedFieldMaterializer()
        do {
            try model.encodePersistedFields(to: &output)
            return output.fields
        } catch let failure {
            throw failure.adaptationError
        }
    }

    public static func field<Value: FieldValueEncodable>(
        identity: FieldIdentity,
        value: borrowing Value,
        entity: String
    ) throws(PersistableEncodingError) -> PersistableField {
        guard let number = UInt32(exactly: identity.number) else {
            throw .invalidSchema(
                entity: entity,
                reason: "field '\(identity.name)' has an invalid number"
            )
        }
        let encodedValue = try value.encodeFieldValue()
        guard !identity.name.isEmpty else {
            throw .invalidSchema(
                entity: entity,
                reason: "a persisted field has an empty name"
            )
        }
        return PersistableField(
            validatedNumber: number,
            validatedName: identity.name,
            value: encodedValue
        )
    }

    public static func object(
        entity: String,
        fields: consuming [PersistableField]
    ) throws(PersistableEncodingError) -> FieldValue {
        do {
            return .object(
                try FieldObject(
                    fields.map { field in
                        (key: field.name, value: field.value)
                    }
                )
            )
        } catch let error {
            switch error {
            case .duplicateKey(let name):
                throw .invalidSchema(
                    entity: entity,
                    reason: "field '\(name)' is declared more than once"
                )
            }
        }
    }

    public static func object<Model: Persistable>(
        from model: borrowing Model
    ) throws(PersistableEncodingError) -> FieldValue {
        try object(
            entity: Model.persistableType,
            fields: encode(model)
        )
    }
}

private struct PersistedFieldMaterializer: PersistedFieldOutput {
    typealias Failure = Never

    private(set) var fields: [PersistableField] = []

    mutating func write<Value: FieldValueEncodable>(
        _ identity: FieldIdentity,
        value: borrowing Value,
        entity: String
    ) throws(PersistableEncodingFailure<Never>) {
        do {
            fields.append(
                try PersistableFieldEncoder.field(
                    identity: identity,
                    value: value,
                    entity: entity
                )
            )
        } catch let error {
            throw .adaptation(error)
        }
    }
}
