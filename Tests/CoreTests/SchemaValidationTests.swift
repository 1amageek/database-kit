import DatabaseTypes
import DatabaseValue
import Foundation
import Testing
@testable import Core
import Vector

@Persistable
private struct SchemaValidationEntity {
    var first: String
    var second: String
}

@Persistable
private struct InvalidScalarIndexEntity {
    #Index(
        ScalarIndexKind<InvalidScalarIndexEntity>(fields: [\.tags]),
        name: "invalid_scalar"
    )

    var tags: [String]
}

@Persistable
private struct InvalidVectorConfigurationEntity {
    #Index(
        VectorIndexKind<InvalidVectorConfigurationEntity>(
            embedding: \.embedding,
            dimensions: 0
        ),
        name: "invalid_vector"
    )

    var embedding: [Float]
}

@Persistable
private struct OptionalScalarIndexEntity {
    #Index(
        ScalarIndexKind<OptionalScalarIndexEntity>(fields: [\.value]),
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
                fields: [
                    FieldSchema(name: "first", fieldNumber: 1, type: .string),
                    FieldSchema(name: "second", fieldNumber: 1, type: .string),
                ]
            )
        }
    }

    @Test("Decoded entity metadata enforces the same invariants")
    func decodedEntityMetadataIsValidated() throws {
        let data = Data("""
        {
          "name": "DecodedEntity",
          "fields": [
            {
              "name": "value",
              "fieldNumber": 1,
              "type": "string",
              "isOptional": false,
              "isArray": false
            },
            {
              "name": "value",
              "fieldNumber": 2,
              "type": "string",
              "isOptional": false,
              "isArray": false
            }
          ],
          "directoryComponents": [],
          "directoryLayer": "default",
          "indexes": [],
          "enumMetadata": {}
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Schema.Entity.self, from: data)
        }
    }

    @Test("Validated field maps preserve both catalog identities")
    func fieldMapsPreserveCatalogIdentities() throws {
        let first = FieldSchema(name: "first", fieldNumber: 1, type: .string)
        let second = FieldSchema(name: "second", fieldNumber: 2, type: .int64)
        let entity = try Schema.Entity(
            name: "MappedEntity",
            fields: [first, second]
        )

        #expect(entity.fieldMapByName == ["first": first, "second": second])
        #expect(entity.fieldMapByNumber == [1: first, 2: second])
    }

    @Test("Duplicate index names fail schema construction")
    func duplicateIndexNamesFailConstruction() throws {
        let first = try IndexDescriptor(
            name: "duplicate_index",
            keyPaths: [\SchemaValidationEntity.first],
            kind: ScalarIndexKind<SchemaValidationEntity>(
                fields: [\SchemaValidationEntity.first]
            )
        )
        let second = try IndexDescriptor(
            name: "duplicate_index",
            keyPaths: [\SchemaValidationEntity.second],
            kind: ScalarIndexKind<SchemaValidationEntity>(
                fields: [\SchemaValidationEntity.second]
            )
        )

        #expect(
            throws: SchemaError.duplicateIndexName(
                indexName: "duplicate_index",
                existingFields: ["first"],
                duplicateFields: ["second"]
            )
        ) {
            try Schema(
                [SchemaValidationEntity.self],
                indexDescriptors: [first, second]
            )
        }
    }

    @Test("Valid declarations produce a complete schema catalog")
    func validDeclarationsProduceSchemaCatalog() throws {
        let schema = try Schema([SchemaValidationEntity.self])

        #expect(schema.entities.map(\.name) == ["SchemaValidationEntity"])
        #expect(schema.entity(for: SchemaValidationEntity.self) != nil)
        #expect(schema.indexDescriptors.isEmpty)
        #expect(schema.allIndexNames.isEmpty)
    }

    @Test("Concrete index field types are enforced by schema construction")
    func concreteIndexFieldTypesAreEnforced() {
        #expect(
            throws: SchemaError.invalidEntity(
                .invalidIndexDeclaration(
                    IndexDeclarationError(
                        indexName: "invalid_scalar",
                        validationError: .unsupportedType(
                            index: "scalar",
                            type: [String].self,
                            reason: "Scalar index requires Comparable types"
                        )
                    )
                )
            )
        ) {
            try Schema([InvalidScalarIndexEntity.self])
        }
    }

    @Test("Index configuration failures reach the schema boundary without trapping")
    func indexConfigurationFailuresReachSchemaBoundary() {
        #expect(
            throws: SchemaError.invalidEntity(
                .invalidIndexDeclaration(
                    IndexDeclarationError(
                        indexName: "invalid_vector",
                        validationError: .invalidConfiguration(
                            index: "vector",
                            reason: "Vector dimensions must be positive"
                        )
                    )
                )
            )
        ) {
            try Schema([InvalidVectorConfigurationEntity.self])
        }
    }

    @Test("Optional comparable fields retain their scalar index contract")
    func optionalComparableFieldsAreAccepted() throws {
        let schema = try Schema([OptionalScalarIndexEntity.self])

        #expect(schema.allIndexNames == ["optional_scalar"])
    }

    @Test("Descriptor key paths must match the concrete index kind")
    func descriptorKeyPathsMustMatchKind() {
        #expect(
            throws: IndexDeclarationError(
                indexName: "mismatched_descriptor",
                validationError: .invalidConfiguration(
                    index: "scalar",
                    reason: "Descriptor key paths must match the index kind fields"
                )
            )
        ) {
            try IndexDescriptor(
                name: "mismatched_descriptor",
                keyPaths: [\SchemaValidationEntity.second],
                kind: ScalarIndexKind<SchemaValidationEntity>(
                    fields: [\SchemaValidationEntity.first]
                )
            )
        }
    }
}
