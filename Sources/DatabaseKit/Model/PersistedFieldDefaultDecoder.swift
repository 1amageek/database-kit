import DatabaseTypes

/// Applies a schema-owned canonical default only when a persisted field is
/// absent, then delegates ordinary model adaptation to a one-value input.
public enum PersistedFieldDefaultDecoder {
    public static func decode<Input: PersistedFieldInput, Value>(
        from input: inout Input,
        for identity: FieldIdentity,
        entity: String,
        defaultValue: () throws(PersistableDecodingError) -> FieldValue,
        decode: (inout PersistedFieldValueInput) throws(
            PersistableDecodingFailure<Never>
        ) -> Value
    ) throws(PersistableDecodingFailure<Input.Failure>) -> Value {
        let value: FieldValue
        if let persisted = try input.readField(identity, entity: entity) {
            value = persisted
        } else {
            do {
                value = try defaultValue()
            } catch let error {
                throw .adaptation(error)
            }
        }

        var resolvedInput = PersistedFieldValueInput(
            identity: identity,
            value: value
        )
        do {
            let decoded = try decode(&resolvedInput)
            try resolvedInput.finish(entity: entity)
            return decoded
        } catch let error {
            throw .adaptation(error.adaptationError)
        }
    }
}
