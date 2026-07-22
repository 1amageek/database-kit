import DatabaseValue

public struct DatabaseRecordFieldDecoder: Sendable {
    private let valuesByName: [String: DatabaseValue]

    public init(
        entity: String,
        fields: [DatabaseObjectField],
        schemas: [FieldSchema]
    ) throws {
        guard !schemas.isEmpty else {
            throw DatabaseRecordDecodingError.missingSchema(entity)
        }

        var schemasByNumber: [Int: FieldSchema] = [:]
        var schemasByName: [String: FieldSchema] = [:]
        for schema in schemas {
            guard schemasByNumber.updateValue(schema, forKey: schema.fieldNumber) == nil else {
                throw DatabaseRecordDecodingError.duplicateSchemaFieldNumber(schema.fieldNumber)
            }
            guard schemasByName.updateValue(schema, forKey: schema.name) == nil else {
                throw DatabaseRecordDecodingError.duplicateSchemaFieldName(schema.name)
            }
        }

        var seenNumbers = Set<UInt32>()
        var values: [String: DatabaseValue] = [:]
        for field in fields {
            guard seenNumbers.insert(field.number).inserted else {
                throw DatabaseRecordDecodingError.duplicateFieldNumber(field.number)
            }
            guard values[field.name] == nil else {
                throw DatabaseRecordDecodingError.duplicateFieldName(field.name)
            }

            let numberSchema = schemasByNumber[Int(field.number)]
            let nameSchema = schemasByName[field.name]
            guard let schema = numberSchema ?? nameSchema else {
                throw DatabaseRecordDecodingError.unknownField(
                    number: field.number,
                    name: field.name
                )
            }
            guard numberSchema?.name == schema.name,
                  nameSchema?.fieldNumber == schema.fieldNumber else {
                throw DatabaseRecordDecodingError.fieldIdentityMismatch(
                    number: field.number,
                    name: field.name
                )
            }
            values[field.name] = field.value
        }
        self.valuesByName = values
    }

    public func decode<Value: DatabaseRecordScalarDecodable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value {
        try Value.decodeDatabaseRecordScalar(requiredValue(for: field), field: field)
    }

    public func decode<Value: Persistable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value {
        let value = try requiredValue(for: field)
        guard case .object(let fields) = value else {
            throw DatabaseRecordDecodingError.invalidValue(field: field, expected: "an object")
        }
        return try Value.decodeDatabaseRecord(fields)
    }

    public func decode<Value: DatabaseRecordReferenceValue>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value {
        let value = try requiredValue(for: field)
        guard case .reference(let identity) = value else {
            throw DatabaseRecordDecodingError.invalidValue(
                field: field,
                expected: "a record reference"
            )
        }
        return try Value.decodeDatabaseRecordReference(identity)
    }

    public func decode<Value: Decodable & Sendable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value {
        try DatabaseValueCodableDecoder.decode(
            type,
            from: requiredValue(for: field)
        )
    }

    public func decode<Value: RawRepresentable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value where Value.RawValue: DatabaseRecordScalarDecodable {
        let rawValue = try Value.RawValue.decodeDatabaseRecordScalar(
            requiredValue(for: field),
            field: field
        )
        guard let value = Value(rawValue: rawValue) else {
            throw DatabaseRecordDecodingError.invalidValue(field: field, expected: "a valid enum raw value")
        }
        return value
    }

    public func decode<Element: DatabaseRecordScalarDecodable>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element] {
        let values = try requiredArray(for: field)
        return try values.map {
            try Element.decodeDatabaseRecordScalar($0, field: field)
        }
    }

    public func decode<Element: Persistable>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element] {
        let values = try requiredArray(for: field)
        return try values.map { value in
            guard case .object(let fields) = value else {
                throw DatabaseRecordDecodingError.invalidValue(field: field, expected: "an array of objects")
            }
            return try Element.decodeDatabaseRecord(fields)
        }
    }

    public func decode<Element: DatabaseRecordReferenceValue>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element] {
        try requiredArray(for: field).map { value in
            guard case .reference(let identity) = value else {
                throw DatabaseRecordDecodingError.invalidValue(
                    field: field,
                    expected: "an array of record references"
                )
            }
            return try Element.decodeDatabaseRecordReference(identity)
        }
    }

    public func decode<Element: RawRepresentable>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element] where Element.RawValue: DatabaseRecordScalarDecodable {
        let values = try requiredArray(for: field)
        return try values.map { value in
            let rawValue = try Element.RawValue.decodeDatabaseRecordScalar(value, field: field)
            guard let element = Element(rawValue: rawValue) else {
                throw DatabaseRecordDecodingError.invalidValue(field: field, expected: "valid enum raw values")
            }
            return element
        }
    }

    public func decodeIfPresent<Value: DatabaseRecordScalarDecodable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value? {
        guard let value = optionalValue(for: field) else { return nil }
        return try Value.decodeDatabaseRecordScalar(value, field: field)
    }

    public func decodeIfPresent<Value: Persistable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value? {
        guard let value = optionalValue(for: field) else { return nil }
        guard case .object(let fields) = value else {
            throw DatabaseRecordDecodingError.invalidValue(field: field, expected: "an object")
        }
        return try Value.decodeDatabaseRecord(fields)
    }

    public func decodeIfPresent<Value: DatabaseRecordReferenceValue>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value? {
        guard let value = optionalValue(for: field) else { return nil }
        guard case .reference(let identity) = value else {
            throw DatabaseRecordDecodingError.invalidValue(
                field: field,
                expected: "a record reference"
            )
        }
        return try Value.decodeDatabaseRecordReference(identity)
    }

    public func decodeIfPresent<Value: Decodable & Sendable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value? {
        guard let value = optionalValue(for: field) else { return nil }
        return try DatabaseValueCodableDecoder.decode(type, from: value)
    }

    public func decodeIfPresent<Value: RawRepresentable>(
        _ type: Value.Type,
        for field: String
    ) throws -> Value? where Value.RawValue: DatabaseRecordScalarDecodable {
        guard let value = optionalValue(for: field) else { return nil }
        let rawValue = try Value.RawValue.decodeDatabaseRecordScalar(value, field: field)
        guard let decoded = Value(rawValue: rawValue) else {
            throw DatabaseRecordDecodingError.invalidValue(field: field, expected: "a valid enum raw value")
        }
        return decoded
    }

    public func decodeIfPresent<Element: DatabaseRecordScalarDecodable>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element]? {
        guard let values = try optionalArray(for: field) else { return nil }
        return try values.map {
            try Element.decodeDatabaseRecordScalar($0, field: field)
        }
    }

    public func decodeIfPresent<Element: Persistable>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element]? {
        guard let values = try optionalArray(for: field) else { return nil }
        return try values.map { value in
            guard case .object(let fields) = value else {
                throw DatabaseRecordDecodingError.invalidValue(field: field, expected: "an array of objects")
            }
            return try Element.decodeDatabaseRecord(fields)
        }
    }

    public func decodeIfPresent<Element: DatabaseRecordReferenceValue>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element]? {
        guard let values = try optionalArray(for: field) else { return nil }
        return try values.map { value in
            guard case .reference(let identity) = value else {
                throw DatabaseRecordDecodingError.invalidValue(
                    field: field,
                    expected: "an array of record references"
                )
            }
            return try Element.decodeDatabaseRecordReference(identity)
        }
    }

    public func decodeIfPresent<Element: RawRepresentable>(
        _ type: [Element].Type,
        for field: String
    ) throws -> [Element]? where Element.RawValue: DatabaseRecordScalarDecodable {
        guard let values = try optionalArray(for: field) else { return nil }
        return try values.map { value in
            let rawValue = try Element.RawValue.decodeDatabaseRecordScalar(value, field: field)
            guard let element = Element(rawValue: rawValue) else {
                throw DatabaseRecordDecodingError.invalidValue(field: field, expected: "valid enum raw values")
            }
            return element
        }
    }

    private func requiredValue(for field: String) throws -> DatabaseValue {
        guard let value = optionalValue(for: field) else {
            throw DatabaseRecordDecodingError.missingRequiredField(field)
        }
        return value
    }

    private func requiredArray(for field: String) throws -> [DatabaseValue] {
        guard case .array(let values) = try requiredValue(for: field) else {
            throw DatabaseRecordDecodingError.invalidValue(field: field, expected: "an array")
        }
        return values
    }

    private func optionalArray(for field: String) throws -> [DatabaseValue]? {
        guard let value = optionalValue(for: field) else { return nil }
        guard case .array(let values) = value else {
            throw DatabaseRecordDecodingError.invalidValue(field: field, expected: "an array")
        }
        return values
    }

    private func optionalValue(for field: String) -> DatabaseValue? {
        guard let value = valuesByName[field] else { return nil }
        if case .null = value { return nil }
        return value
    }
}
