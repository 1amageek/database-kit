import DatabaseTypes

public extension PersistedFieldInput {
    mutating func decode<Value: FieldValueDecodable>(
        _ type: Value.Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> Value {
        let value = try requiredValue(for: identity, entity: entity)
        do {
            return try Value.decodeFieldValue(value, field: identity.name)
        } catch let error {
            throw .adaptation(error)
        }
    }

    mutating func decode<Value: Persistable>(
        _ type: Value.Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> Value {
        let value = try requiredValue(for: identity, entity: entity)
        guard case .object(let object) = value else {
            throw .adaptation(
                .invalidValue(
                    field: identity.name,
                    expected: "an object"
                )
            )
        }
        do {
            return try Value.decodePersistedObject(object)
        } catch let error {
            throw .adaptation(error)
        }
    }

    mutating func decode<Value: PersistableReferenceValue>(
        _ type: Value.Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> Value {
        let value = try requiredValue(for: identity, entity: entity)
        guard case .reference(let reference) = value else {
            throw .adaptation(
                .invalidValue(
                    field: identity.name,
                    expected: "a persistable reference"
                )
            )
        }
        do {
            return try Value.decodePersistedReference(reference)
        } catch let error {
            throw .adaptation(
                .invalidReference(field: identity.name, reason: error)
            )
        }
    }

    mutating func decode<Value: RawRepresentable>(
        _ type: Value.Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> Value
    where Value.RawValue: FieldValueDecodable {
        let value = try requiredValue(for: identity, entity: entity)
        let rawValue: Value.RawValue
        do {
            rawValue = try Value.RawValue.decodeFieldValue(
                value,
                field: identity.name
            )
        } catch let error {
            throw .adaptation(error)
        }
        guard let decoded = Value(rawValue: rawValue) else {
            throw .adaptation(
                .invalidValue(
                    field: identity.name,
                    expected: "a valid enum raw value"
                )
            )
        }
        return decoded
    }

    mutating func decode<Element: FieldValueDecodable>(
        _ type: [Element].Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> [Element] {
        let values = try requiredArray(for: identity, entity: entity)
        var decoded: [Element] = []
        decoded.reserveCapacity(values.count)
        do {
            for value in values {
                decoded.append(
                    try Element.decodeFieldValue(
                        value,
                        field: identity.name
                    )
                )
            }
        } catch let error {
            throw .adaptation(error)
        }
        return decoded
    }

    mutating func decode<Element: Persistable>(
        _ type: [Element].Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> [Element] {
        let values = try requiredArray(for: identity, entity: entity)
        var decoded: [Element] = []
        decoded.reserveCapacity(values.count)
        for value in values {
            guard case .object(let object) = value else {
                throw .adaptation(
                    .invalidValue(
                        field: identity.name,
                        expected: "an array of objects"
                    )
                )
            }
            do {
                decoded.append(try Element.decodePersistedObject(object))
            } catch let error {
                throw .adaptation(error)
            }
        }
        return decoded
    }

    mutating func decode<Element: PersistableReferenceValue>(
        _ type: [Element].Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> [Element] {
        let values = try requiredArray(for: identity, entity: entity)
        var decoded: [Element] = []
        decoded.reserveCapacity(values.count)
        for value in values {
            guard case .reference(let reference) = value else {
                throw .adaptation(
                    .invalidValue(
                        field: identity.name,
                        expected: "an array of persistable references"
                    )
                )
            }
            do {
                decoded.append(
                    try Element.decodePersistedReference(reference)
                )
            } catch let error {
                throw .adaptation(
                    .invalidReference(field: identity.name, reason: error)
                )
            }
        }
        return decoded
    }

    mutating func decode<Element: RawRepresentable>(
        _ type: [Element].Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> [Element]
    where Element.RawValue: FieldValueDecodable {
        let values = try requiredArray(for: identity, entity: entity)
        var decoded: [Element] = []
        decoded.reserveCapacity(values.count)
        for value in values {
            let rawValue: Element.RawValue
            do {
                rawValue = try Element.RawValue.decodeFieldValue(
                    value,
                    field: identity.name
                )
            } catch let error {
                throw .adaptation(error)
            }
            guard let element = Element(rawValue: rawValue) else {
                throw .adaptation(
                    .invalidValue(
                        field: identity.name,
                        expected: "valid enum raw values"
                    )
                )
            }
            decoded.append(element)
        }
        return decoded
    }

    mutating func decodeIfPresent<Value: FieldValueDecodable>(
        _ type: Value.Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> Value? {
        guard let value = try optionalValue(
            for: identity,
            entity: entity
        ) else {
            return nil
        }
        do {
            return try Value.decodeFieldValue(value, field: identity.name)
        } catch let error {
            throw .adaptation(error)
        }
    }

    mutating func decodeIfPresent<Value: Persistable>(
        _ type: Value.Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> Value? {
        guard let value = try optionalValue(
            for: identity,
            entity: entity
        ) else {
            return nil
        }
        guard case .object(let object) = value else {
            throw .adaptation(
                .invalidValue(
                    field: identity.name,
                    expected: "an object"
                )
            )
        }
        do {
            return try Value.decodePersistedObject(object)
        } catch let error {
            throw .adaptation(error)
        }
    }

    mutating func decodeIfPresent<Value: PersistableReferenceValue>(
        _ type: Value.Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> Value? {
        guard let value = try optionalValue(
            for: identity,
            entity: entity
        ) else {
            return nil
        }
        guard case .reference(let reference) = value else {
            throw .adaptation(
                .invalidValue(
                    field: identity.name,
                    expected: "a persistable reference"
                )
            )
        }
        do {
            return try Value.decodePersistedReference(reference)
        } catch let error {
            throw .adaptation(
                .invalidReference(field: identity.name, reason: error)
            )
        }
    }

    mutating func decodeIfPresent<Value: RawRepresentable>(
        _ type: Value.Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> Value?
    where Value.RawValue: FieldValueDecodable {
        guard let value = try optionalValue(
            for: identity,
            entity: entity
        ) else {
            return nil
        }
        let rawValue: Value.RawValue
        do {
            rawValue = try Value.RawValue.decodeFieldValue(
                value,
                field: identity.name
            )
        } catch let error {
            throw .adaptation(error)
        }
        guard let decoded = Value(rawValue: rawValue) else {
            throw .adaptation(
                .invalidValue(
                    field: identity.name,
                    expected: "a valid enum raw value"
                )
            )
        }
        return decoded
    }

    mutating func decodeIfPresent<Element: FieldValueDecodable>(
        _ type: [Element].Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> [Element]? {
        guard let values = try optionalArray(
            for: identity,
            entity: entity
        ) else {
            return nil
        }
        var decoded: [Element] = []
        decoded.reserveCapacity(values.count)
        do {
            for value in values {
                decoded.append(
                    try Element.decodeFieldValue(
                        value,
                        field: identity.name
                    )
                )
            }
        } catch let error {
            throw .adaptation(error)
        }
        return decoded
    }

    mutating func decodeIfPresent<Element: Persistable>(
        _ type: [Element].Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> [Element]? {
        guard let values = try optionalArray(
            for: identity,
            entity: entity
        ) else {
            return nil
        }
        var decoded: [Element] = []
        decoded.reserveCapacity(values.count)
        for value in values {
            guard case .object(let object) = value else {
                throw .adaptation(
                    .invalidValue(
                        field: identity.name,
                        expected: "an array of objects"
                    )
                )
            }
            do {
                decoded.append(try Element.decodePersistedObject(object))
            } catch let error {
                throw .adaptation(error)
            }
        }
        return decoded
    }

    mutating func decodeIfPresent<
        Element: PersistableReferenceValue
    >(
        _ type: [Element].Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> [Element]? {
        guard let values = try optionalArray(
            for: identity,
            entity: entity
        ) else {
            return nil
        }
        var decoded: [Element] = []
        decoded.reserveCapacity(values.count)
        for value in values {
            guard case .reference(let reference) = value else {
                throw .adaptation(
                    .invalidValue(
                        field: identity.name,
                        expected: "an array of persistable references"
                    )
                )
            }
            do {
                decoded.append(
                    try Element.decodePersistedReference(reference)
                )
            } catch let error {
                throw .adaptation(
                    .invalidReference(field: identity.name, reason: error)
                )
            }
        }
        return decoded
    }

    mutating func decodeIfPresent<Element: RawRepresentable>(
        _ type: [Element].Type,
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> [Element]?
    where Element.RawValue: FieldValueDecodable {
        guard let values = try optionalArray(
            for: identity,
            entity: entity
        ) else {
            return nil
        }
        var decoded: [Element] = []
        decoded.reserveCapacity(values.count)
        for value in values {
            let rawValue: Element.RawValue
            do {
                rawValue = try Element.RawValue.decodeFieldValue(
                    value,
                    field: identity.name
                )
            } catch let error {
                throw .adaptation(error)
            }
            guard let element = Element(rawValue: rawValue) else {
                throw .adaptation(
                    .invalidValue(
                        field: identity.name,
                        expected: "valid enum raw values"
                    )
                )
            }
            decoded.append(element)
        }
        return decoded
    }

    private mutating func requiredValue(
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> FieldValue {
        guard let value = try optionalValue(
            for: identity,
            entity: entity
        ) else {
            throw .adaptation(.missingRequiredField(identity.name))
        }
        return value
    }

    private mutating func requiredArray(
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> [FieldValue] {
        let value = try requiredValue(for: identity, entity: entity)
        guard case .array(let values) = value else {
            throw .adaptation(
                .invalidValue(
                    field: identity.name,
                    expected: "an array"
                )
            )
        }
        return values
    }

    private mutating func optionalArray(
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> [FieldValue]? {
        guard let value = try optionalValue(
            for: identity,
            entity: entity
        ) else {
            return nil
        }
        guard case .array(let values) = value else {
            throw .adaptation(
                .invalidValue(
                    field: identity.name,
                    expected: "an array"
                )
            )
        }
        return values
    }

    private mutating func optionalValue(
        for identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> FieldValue? {
        guard let value = try readField(identity, entity: entity) else {
            return nil
        }
        if case .null = value {
            return nil
        }
        return value
    }
}
