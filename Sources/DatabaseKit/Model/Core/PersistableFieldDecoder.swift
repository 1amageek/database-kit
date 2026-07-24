import DatabaseTypes

public struct PersistableFieldDecoder: Sendable {
    private let valuesByName: [String: FieldValue]

    public init(
        entity: String,
        fields: [PersistableField],
        schemas: [FieldSchema]
    ) throws {
        guard !schemas.isEmpty else {
            throw PersistableDecodingError.missingSchema(entity)
        }

        var schemasByNumber: [Int: FieldSchema] = [:]
        var schemasByName: [String: FieldSchema] = [:]
        for schema in schemas {
            guard schemasByNumber.updateValue(schema, forKey: schema.fieldNumber) == nil else {
                throw PersistableDecodingError.duplicateSchemaFieldNumber(schema.fieldNumber)
            }
            guard schemasByName.updateValue(schema, forKey: schema.name) == nil else {
                throw PersistableDecodingError.duplicateSchemaFieldName(schema.name)
            }
        }

        var seenNumbers = Set<UInt32>()
        var values: [String: FieldValue] = [:]
        for field in fields {
            guard seenNumbers.insert(field.number).inserted else {
                throw PersistableDecodingError.duplicateFieldNumber(field.number)
            }
            guard values[field.name] == nil else {
                throw PersistableDecodingError.duplicateFieldName(field.name)
            }

            let numberSchema = schemasByNumber[Int(field.number)]
            let nameSchema = schemasByName[field.name]
            guard let schema = numberSchema ?? nameSchema else {
                throw PersistableDecodingError.unknownField(
                    number: field.number,
                    name: field.name
                )
            }
            guard numberSchema?.name == schema.name,
                  nameSchema?.fieldNumber == schema.fieldNumber else {
                throw PersistableDecodingError.fieldIdentityMismatch(
                    number: field.number,
                    name: field.name
                )
            }
            values[field.name] = field.value
        }
        self.valuesByName = values
    }

    public func decode<Value: PersistableScalarDecodable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value {
        try Value.decodePersistedScalar(requiredValue(for: field), field: field)
    }

    public func decode<Value: Persistable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value {
        let value = try requiredValue(for: field)
        guard case .object(let fields) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an object")
        }
        return try Value.decodePersistedObject(fields)
    }

    public func decode<Value: PersistableReferenceValue>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value {
        let value = try requiredValue(for: field)
        guard case .reference(let identity) = value else {
            throw PersistableDecodingError.invalidValue(
                field: field,
                expected: "a persistable reference"
            )
        }
        return try Value.decodePersistedReference(identity)
    }

    public func decode<Value: Decodable & Sendable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value {
        try FieldValueCodableDecoder.decode(
            type,
            from: requiredValue(for: field)
        )
    }

    public func decode<Value: RawRepresentable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value where Value.RawValue: PersistableScalarDecodable {
        let rawValue = try Value.RawValue.decodePersistedScalar(
            requiredValue(for: field),
            field: field
        )
        guard let value = Value(rawValue: rawValue) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a valid enum raw value")
        }
        return value
    }

    public func decode<Element: PersistableScalarDecodable>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element] {
        let values = try requiredArray(for: field)
        return try values.map {
            try Element.decodePersistedScalar($0, field: field)
        }
    }

    public func decode<Element: Persistable>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element] {
        let values = try requiredArray(for: field)
        return try values.map { value in
            guard case .object(let fields) = value else {
                throw PersistableDecodingError.invalidValue(field: field, expected: "an array of objects")
            }
            return try Element.decodePersistedObject(fields)
        }
    }

    public func decode<Element: PersistableReferenceValue>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element] {
        try requiredArray(for: field).map { value in
            guard case .reference(let identity) = value else {
                throw PersistableDecodingError.invalidValue(
                    field: field,
                    expected: "an array of persistable references"
                )
            }
            return try Element.decodePersistedReference(identity)
        }
    }

    public func decode<Element: RawRepresentable>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element] where Element.RawValue: PersistableScalarDecodable {
        let values = try requiredArray(for: field)
        return try values.map { value in
            let rawValue = try Element.RawValue.decodePersistedScalar(value, field: field)
            guard let element = Element(rawValue: rawValue) else {
                throw PersistableDecodingError.invalidValue(field: field, expected: "valid enum raw values")
            }
            return element
        }
    }

    public func decodeIfPresent<Value: PersistableScalarDecodable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value? {
        guard let value = optionalValue(for: field) else { return nil }
        return try Value.decodePersistedScalar(value, field: field)
    }

    public func decodeIfPresent<Value: Persistable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value? {
        guard let value = optionalValue(for: field) else { return nil }
        guard case .object(let fields) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an object")
        }
        return try Value.decodePersistedObject(fields)
    }

    public func decodeIfPresent<Value: PersistableReferenceValue>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value? {
        guard let value = optionalValue(for: field) else { return nil }
        guard case .reference(let identity) = value else {
            throw PersistableDecodingError.invalidValue(
                field: field,
                expected: "a persistable reference"
            )
        }
        return try Value.decodePersistedReference(identity)
    }

    public func decodeIfPresent<Value: Decodable & Sendable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value? {
        guard let value = optionalValue(for: field) else { return nil }
        return try FieldValueCodableDecoder.decode(type, from: value)
    }

    public func decodeIfPresent<Value: RawRepresentable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value? where Value.RawValue: PersistableScalarDecodable {
        guard let value = optionalValue(for: field) else { return nil }
        let rawValue = try Value.RawValue.decodePersistedScalar(value, field: field)
        guard let decoded = Value(rawValue: rawValue) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a valid enum raw value")
        }
        return decoded
    }

    public func decodeIfPresent<Element: PersistableScalarDecodable>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element]? {
        guard let values = try optionalArray(for: field) else { return nil }
        return try values.map {
            try Element.decodePersistedScalar($0, field: field)
        }
    }

    public func decodeIfPresent<Element: Persistable>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element]? {
        guard let values = try optionalArray(for: field) else { return nil }
        return try values.map { value in
            guard case .object(let fields) = value else {
                throw PersistableDecodingError.invalidValue(field: field, expected: "an array of objects")
            }
            return try Element.decodePersistedObject(fields)
        }
    }

    public func decodeIfPresent<Element: PersistableReferenceValue>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element]? {
        guard let values = try optionalArray(for: field) else { return nil }
        return try values.map { value in
            guard case .reference(let identity) = value else {
                throw PersistableDecodingError.invalidValue(
                    field: field,
                    expected: "an array of persistable references"
                )
            }
            return try Element.decodePersistedReference(identity)
        }
    }

    public func decodeIfPresent<Element: RawRepresentable>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element]? where Element.RawValue: PersistableScalarDecodable {
        guard let values = try optionalArray(for: field) else { return nil }
        return try values.map { value in
            let rawValue = try Element.RawValue.decodePersistedScalar(value, field: field)
            guard let element = Element(rawValue: rawValue) else {
                throw PersistableDecodingError.invalidValue(field: field, expected: "valid enum raw values")
            }
            return element
        }
    }

    private func requiredValue(for field: String) throws -> FieldValue {
        guard let value = optionalValue(for: field) else {
            throw PersistableDecodingError.missingRequiredField(field)
        }
        return value
    }

    private func requiredArray(for field: String) throws -> [FieldValue] {
        guard case .array(let values) = try requiredValue(for: field) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an array")
        }
        return values
    }

    private func optionalArray(for field: String) throws -> [FieldValue]? {
        guard let value = optionalValue(for: field) else { return nil }
        guard case .array(let values) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an array")
        }
        return values
    }

    private func optionalValue(for field: String) -> FieldValue? {
        guard let value = valuesByName[field] else { return nil }
        if case .null = value { return nil }
        return value
    }
}
