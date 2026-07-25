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

    /// Encode only the field matching one canonical schema identity.
    ///
    /// The generated model traversal visits field declarations without
    /// materializing unrelated values. This is the canonical fallback for
    /// execution paths that cannot retain a typed field accessor.
    public static func value<Model: Persistable>(
        for field: FieldIdentity,
        in model: borrowing Model
    ) throws(PersistableEncodingError) -> FieldValue? {
        guard field.number > 0, !field.name.isEmpty else {
            throw .invalidSchema(
                entity: Model.persistableType,
                reason: "a requested field identity is invalid"
            )
        }

        var output = SelectedPersistedFieldOutput(
            requestedField: field,
            expectedEntity: Model.persistableType
        )
        do {
            try model.encodePersistedFields(to: &output)
        } catch let failure {
            switch failure {
            case .adaptation(let error), .output(let error):
                throw error
            }
        }
        return output.selectedValue
    }

    public static func object(
        entity: String,
        fields: consuming [PersistableField]
    ) throws(PersistableEncodingError) -> FieldObject {
        do {
            return try FieldObject(
                fields.map { field in
                    (key: field.name, value: field.value)
                }
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
    ) throws(PersistableEncodingError) -> FieldObject {
        try object(
            entity: Model.persistableType,
            fields: encode(model)
        )
    }
}

private struct SelectedPersistedFieldOutput: PersistedFieldOutput {
    typealias Failure = PersistableEncodingError

    let requestedField: FieldIdentity
    let expectedEntity: String
    private(set) var selectedValue: FieldValue?

    mutating func write<Value: FieldValueEncodable>(
        _ identity: FieldIdentity,
        value: borrowing Value,
        entity: String
    ) throws(PersistableEncodingFailure<PersistableEncodingError>) {
        guard entity == expectedEntity else {
            throw .output(
                .invalidSchema(
                    entity: expectedEntity,
                    reason: "field '\(identity.name)' was emitted for entity '\(entity)'"
                )
            )
        }

        let numberMatches = identity.number == requestedField.number
        let nameMatches = identity.name == requestedField.name
        guard numberMatches || nameMatches else {
            return
        }
        guard numberMatches && nameMatches else {
            throw .output(
                .invalidSchema(
                    entity: expectedEntity,
                    reason: "field identity '\(requestedField.name)#\(requestedField.number)' does not match '\(identity.name)#\(identity.number)'"
                )
            )
        }
        guard selectedValue == nil else {
            throw .output(
                .invalidSchema(
                    entity: expectedEntity,
                    reason: "field '\(identity.name)' was emitted more than once"
                )
            )
        }

        do {
            selectedValue = try value.encodeFieldValue()
        } catch let error {
            throw .output(error)
        }
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
