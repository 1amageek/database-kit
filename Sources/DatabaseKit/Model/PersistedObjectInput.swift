import DatabaseTypes

/// A zero-copy semantic input over an existing canonical object.
///
/// `FieldObject` retains its canonical field storage. This input validates
/// schema membership without rebuilding the object as `PersistableField`
/// values or a dictionary.
public struct PersistedObjectInput: PersistedFieldInput, Sendable {
    public typealias Failure = Never

    private let object: FieldObject

    public init(
        entity: String,
        object: FieldObject,
        schemas: [FieldSchema]
    ) throws(PersistableDecodingError) {
        guard !schemas.isEmpty else {
            throw .missingSchema(entity)
        }

        var schemaNames: [String] = []
        var schemaNumbers = Set<Int>()
        schemaNames.reserveCapacity(schemas.count)
        schemaNumbers.reserveCapacity(schemas.count)
        for schema in schemas {
            guard schemaNumbers.insert(schema.fieldNumber).inserted else {
                throw .duplicateSchemaFieldNumber(schema.fieldNumber)
            }
            guard !schemaNames.contains(where: {
                Self.sameName($0, schema.name)
            }) else {
                throw .duplicateSchemaFieldName(schema.name)
            }
            schemaNames.append(schema.name)
        }
        for field in object.fields {
            guard schemaNames.contains(where: {
                Self.sameName($0, field.key)
            }) else {
                throw .unknownField(number: 0, name: field.key)
            }
        }
        self.object = object
    }

    public mutating func readField(
        _ identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Never>) -> FieldValue? {
        guard identity.number > 0, !identity.name.isEmpty else {
            throw .adaptation(
                .invalidFieldIdentity(
                    entity: entity,
                    number: identity.number,
                    name: identity.name
                )
            )
        }
        return object[identity.name]
    }

    public func finish(
        entity: String
    ) throws(PersistableDecodingFailure<Never>) {}

    private static func sameName(_ left: String, _ right: String) -> Bool {
        left.utf8.elementsEqual(right.utf8)
    }
}
