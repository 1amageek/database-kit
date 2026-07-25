import DatabaseTypes
import Testing
@testable import DatabaseKit

@Persistable
private struct SchemaValidationEntity {
    var id: String = "fixture-id"
    var first: String
    var second: String
}

@Persistable
private struct InvalidScalarIndexEntity {
    var id: String = "fixture-id"
    #Index(
        .scalar,
        fields: [\InvalidScalarIndexEntity.tags],
        name: "invalid_scalar"
    )

    var tags: [String]
}

@Persistable
private struct InvalidVectorConfigurationEntity {
    var id: String = "fixture-id"
    #Index(
        .vector(dimensions: 0),
        embedding: \InvalidVectorConfigurationEntity.embedding,
        name: "invalid_vector"
    )

    var embedding: Vector
}

@Persistable
private struct OptionalScalarIndexEntity {
    var id: String = "fixture-id"
    #Index(
        .scalar,
        fields: [\OptionalScalarIndexEntity.value],
        name: "optional_scalar"
    )

    var value: String?
}

@Suite("Schema Validation")
struct SchemaValidationTests {
    @Test("Duplicate entity names fail schema construction")
    func duplicateEntityNamesFailConstruction() throws {
        let entity = try Schema.Entity(
            name: "DuplicateEntity",
            identifierType: .string,
            fields: []
        )

        #expect(throws: SchemaError.duplicateEntityName("DuplicateEntity")) {
            try Schema(entities: [entity, entity])
        }
    }

    @Test("Duplicate field names fail entity construction without trapping")
    func duplicateFieldNamesFailEntityConstruction() {
        #expect(
            throws: SchemaEntityError.duplicateFieldName("value")
        ) {
            try Schema.Entity(
                name: "DuplicateFieldName",
                identifierType: .string,
                fields: [
                    FieldSchema(name: "value", fieldNumber: 1, type: .string),
                    FieldSchema(name: "value", fieldNumber: 2, type: .string),
                ]
            )
        }
    }

    @Test("Duplicate field numbers fail entity construction without trapping")
    func duplicateFieldNumbersFailEntityConstruction() {
        #expect(
            throws: SchemaEntityError.duplicateFieldNumber(
                fieldNumber: 1,
                fieldNames: ["first", "second"]
            )
        ) {
            try Schema.Entity(
                name: "DuplicateFieldNumber",
                identifierType: .string,
                fields: [
                    FieldSchema(name: "first", fieldNumber: 1, type: .string),
                    FieldSchema(name: "second", fieldNumber: 1, type: .string),
                ]
            )
        }
    }

    @Test("Validated field maps preserve both catalog identities")
    func fieldMapsPreserveCatalogIdentities() throws {
        let first = FieldSchema(name: "first", fieldNumber: 1, type: .string)
        let second = FieldSchema(name: "second", fieldNumber: 2, type: .int64)
        let entity = try Schema.Entity(
            name: "MappedEntity",
            identifierType: .string,
            fields: [first, second]
        )

        #expect(entity.fieldMapByName == ["first": first, "second": second])
        #expect(entity.fieldMapByNumber == [1: first, 2: second])
    }

    @Test("Reference targets must exist in the complete schema")
    func referenceTargetsMustExist() throws {
        let entity = try Schema.Entity(
            name: "ReferenceOwner",
            identifierType: .string,
            fields: [
                FieldSchema(
                    name: "target",
                    fieldNumber: 1,
                    type: .reference,
                    referenceTargetEntity: "MissingTarget"
                )
            ]
        )

        #expect(
            throws: SchemaError.unknownReferenceTarget(
                entity: "ReferenceOwner",
                field: "target",
                target: "MissingTarget"
            )
        ) {
            try Schema(entities: [entity])
        }
    }

    @Test("Schema equality compares complete entity metadata")
    func schemaEqualityComparesMetadata() throws {
        let first = try Schema(
            entities: [
                Schema.Entity(
                    name: "ComparableEntity",
                    identifierType: .string,
                    fields: [
                        FieldSchema(
                            name: "value",
                            fieldNumber: 1,
                            type: .string
                        )
                    ]
                )
            ]
        )
        let second = try Schema(
            entities: [
                Schema.Entity(
                    name: "ComparableEntity",
                    identifierType: .string,
                    fields: [
                        FieldSchema(
                            name: "value",
                            fieldNumber: 1,
                            type: .int64
                        )
                    ]
                )
            ]
        )

        #expect(first != second)
    }

    @Test("Duplicate index names fail schema construction")
    func duplicateIndexNamesFailConstruction() throws {
        let first = try IndexDescriptor(
            name: "duplicate_index",
            definition: .scalar,
            fields: [SchemaValidationEntity.fields.first.ascending]
        )
        let second = try IndexDescriptor(
            name: "duplicate_index",
            definition: .scalar,
            fields: [SchemaValidationEntity.fields.second.ascending]
        )
        let firstEntity = try Schema.Entity(
            name: "FirstIndexedEntity",
            identifierType: .string,
            fields: SchemaValidationEntity.fieldSchemas,
            indexes: [IndexDescriptorMetadata(first)]
        )
        let secondEntity = try Schema.Entity(
            name: "SecondIndexedEntity",
            identifierType: .string,
            fields: SchemaValidationEntity.fieldSchemas,
            indexes: [IndexDescriptorMetadata(second)]
        )

        #expect(
            throws: SchemaError.duplicateIndexName(
                indexName: "duplicate_index",
                existingFields: ["first"],
                duplicateFields: ["second"]
            )
        ) {
            try Schema(
                entities: [firstEntity, secondEntity]
            )
        }
    }

    @Test("Valid declarations produce a complete schema catalog")
    func validDeclarationsProduceSchemaCatalog() throws {
        let schema = try Schema(
            entities: [try SchemaValidationEntity.schemaEntity]
        )

        #expect(schema.entities.map(\.name) == ["SchemaValidationEntity"])
        #expect(schema.entity(for: SchemaValidationEntity.self) != nil)
        #expect(schema.indexDescriptors.isEmpty)
        #expect(schema.allIndexNames.isEmpty)
    }

    @Test("Concrete index field types are enforced by schema construction")
    func concreteIndexFieldTypesAreEnforced() {
        #expect(
            throws: SchemaEntityError.invalidIndexDeclaration(
                IndexDeclarationError(
                    indexName: "invalid_scalar",
                    validationError: .unsupportedField(
                        index: "scalar",
                        field: FieldSchema(
                            name: "tags",
                            fieldNumber: 2,
                            type: .string,
                            isArray: true
                        ),
                        reason: "Scalar index requires fields with canonical ordering"
                    )
                )
            )
        ) {
            _ = try InvalidScalarIndexEntity.schemaEntity
        }
    }

    @Test("Index configuration failures reach the schema boundary without trapping")
    func indexConfigurationFailuresReachSchemaBoundary() {
        #expect(
            throws: SchemaEntityError.invalidIndexDeclaration(
                IndexDeclarationError(
                    indexName: "invalid_vector",
                    validationError: .invalidConfiguration(
                        index: "vector",
                        reason: "Vector dimensions must be positive"
                    )
                )
            )
        ) {
            _ = try InvalidVectorConfigurationEntity.schemaEntity
        }
    }

    @Test("Optional comparable fields retain their scalar index contract")
    func optionalComparableFieldsAreAccepted() throws {
        let schema = try Schema(
            entities: [try OptionalScalarIndexEntity.schemaEntity]
        )

        #expect(schema.allIndexNames == ["optional_scalar"])
    }

    @Test("Descriptor field identities must match the static schema")
    func descriptorFieldIdentitiesMustMatchSchema() {
        #expect(
            throws: IndexDeclarationError(
                indexName: "mismatched_descriptor",
                validationError: .invalidConfiguration(
                    index: "scalar",
                    reason: "Field identity 'first#3' is absent from the static schema"
                )
            )
        ) {
            try IndexDescriptor(
                name: "mismatched_descriptor",
                definition: .scalar,
                fields: [
                    Field<SchemaValidationEntity, String>(
                        identity: FieldIdentity(name: "first", number: 3),
                        type: .string
                    ).ascending
                ]
            )
        }
    }
}
