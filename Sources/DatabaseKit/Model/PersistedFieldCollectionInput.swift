import DatabaseTypes

/// An owned field input for callers that already materialized a complete model
/// field collection.
///
/// Construction validates the complete schema identity and canonicalizes field
/// order once. Reading then advances monotonically by stable field number.
public struct PersistedFieldCollectionInput: PersistedFieldInput, Sendable {
    public typealias Failure = Never

    private let fields: [PersistableField]
    private var nextIndex: Int

    public init(
        entity: String,
        fields: consuming [PersistableField],
        schemas: [FieldSchema]
    ) throws(PersistableDecodingError) {
        guard !schemas.isEmpty else {
            throw .missingSchema(entity)
        }

        var schemasByNumber: [Int: FieldSchema] = [:]
        schemasByNumber.reserveCapacity(schemas.count)
        var schemaNames: [String] = []
        schemaNames.reserveCapacity(schemas.count)
        for schema in schemas {
            guard schemasByNumber.updateValue(
                schema,
                forKey: schema.fieldNumber
            ) == nil else {
                throw .duplicateSchemaFieldNumber(schema.fieldNumber)
            }
            guard !schemaNames.contains(where: {
                Self.sameName($0, schema.name)
            }) else {
                throw .duplicateSchemaFieldName(schema.name)
            }
            schemaNames.append(schema.name)
        }

        var fields = fields
        var seenNumbers = Set<UInt32>()
        var seenNames: [String] = []
        seenNumbers.reserveCapacity(fields.count)
        seenNames.reserveCapacity(fields.count)
        for field in fields {
            guard seenNumbers.insert(field.number).inserted else {
                throw .duplicateFieldNumber(field.number)
            }
            guard !seenNames.contains(where: {
                Self.sameName($0, field.name)
            }) else {
                throw .duplicateFieldName(field.name)
            }
            seenNames.append(field.name)

            let numberSchema = schemasByNumber[Int(field.number)]
            let nameSchema = schemas.first {
                Self.sameName($0.name, field.name)
            }
            guard let schema = numberSchema ?? nameSchema else {
                throw .unknownField(
                    number: field.number,
                    name: field.name
                )
            }
            guard numberSchema?.name == schema.name,
                  nameSchema?.fieldNumber == schema.fieldNumber else {
                throw .fieldIdentityMismatch(
                    number: field.number,
                    name: field.name
                )
            }
        }

        if !Self.isOrderedByFieldNumber(fields) {
            fields.sort { left, right in
                left.number < right.number
            }
        }
        self.fields = fields
        self.nextIndex = fields.startIndex
    }

    public mutating func readField(
        _ identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Never>) -> FieldValue? {
        guard let expectedNumber = UInt32(exactly: identity.number),
              expectedNumber > 0 else {
            throw .adaptation(
                .invalidFieldIdentity(
                    entity: entity,
                    number: identity.number,
                    name: identity.name
                )
            )
        }
        guard nextIndex < fields.endIndex else {
            return nil
        }

        let field = fields[nextIndex]
        guard field.number >= expectedNumber else {
            throw .adaptation(
                .unexpectedFieldOrder(
                    entity: entity,
                    expectedNumber: expectedNumber,
                    actualNumber: field.number
                )
            )
        }
        guard field.number == expectedNumber else {
            return nil
        }
        guard Self.sameName(field.name, identity.name) else {
            throw .adaptation(
                .fieldIdentityMismatch(
                    number: field.number,
                    name: field.name
                )
            )
        }

        nextIndex += 1
        return field.value
    }

    public func finish(
        entity: String
    ) throws(PersistableDecodingFailure<Never>) {
        guard nextIndex == fields.endIndex else {
            let field = fields[nextIndex]
            throw .adaptation(
                .unconsumedField(
                    entity: entity,
                    number: field.number,
                    name: field.name
                )
            )
        }
    }

    private static func isOrderedByFieldNumber(
        _ fields: [PersistableField]
    ) -> Bool {
        for index in fields.indices.dropFirst() {
            guard fields[index - 1].number < fields[index].number else {
                return false
            }
        }
        return true
    }

    private static func sameName(_ left: String, _ right: String) -> Bool {
        left.utf8.elementsEqual(right.utf8)
    }
}
