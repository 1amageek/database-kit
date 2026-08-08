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
private struct ArrayScalarIndexEntity {
    var id: String = "fixture-id"
    #Index(
        .scalar,
        fields: [\ArrayScalarIndexEntity.tags],
        name: "tags"
    )

    var tags: [String]
}

@Persistable
private struct CompositeArrayScalarIndexEntity {
    var id: String = "fixture-id"
    #Index(
        .scalar,
        fields: [
            \CompositeArrayScalarIndexEntity.category,
            \CompositeArrayScalarIndexEntity.tags,
        ],
        name: "category_tags"
    )

    var category: String
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

    @Test("Field access rules require exact schema identity")
    func fieldAccessRulesRequireExactIdentity() {
        #expect(
            throws: SchemaEntityError.invalidFieldAccessRule(
                fieldName: "value",
                fieldNumber: 2
            )
        ) {
            try Schema.Entity(
                name: "RestrictedEntity",
                identifierType: .string,
                fields: [
                    FieldSchema(
                        name: "value",
                        fieldNumber: 1,
                        type: .string
                    )
                ],
                fieldAccessRules: [
                    FieldAccessRule(
                        field: FieldIdentity(
                            name: "value",
                            number: 2
                        ),
                        read: .authenticated,
                        write: .roles(["admin"])
                    )
                ]
            )
        }
    }

    @Test("Each field has at most one access rule")
    func fieldAccessRulesAreUnique() {
        let field = FieldIdentity(name: "value", number: 1)
        #expect(
            throws: SchemaEntityError.duplicateFieldAccessRule("value")
        ) {
            try Schema.Entity(
                name: "RestrictedEntity",
                identifierType: .string,
                fields: [
                    FieldSchema(
                        name: "value",
                        fieldNumber: 1,
                        type: .string
                    )
                ],
                fieldAccessRules: [
                    FieldAccessRule(
                        field: field,
                        read: .authenticated,
                        write: .roles(["admin"])
                    ),
                    FieldAccessRule(
                        field: field,
                        read: .roles(["manager"]),
                        write: .roles(["admin"])
                    )
                ]
            )
        }
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
            indexes: [
                IndexDescriptorMetadata(
                    entityName: "FirstIndexedEntity",
                    name: first.name,
                    kind: first.kind
                )
            ]
        )
        let secondEntity = try Schema.Entity(
            name: "SecondIndexedEntity",
            identifierType: .string,
            fields: SchemaValidationEntity.fieldSchemas,
            indexes: [
                IndexDescriptorMetadata(
                    entityName: "SecondIndexedEntity",
                    name: second.name,
                    kind: second.kind
                )
            ]
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

    @Test("Index metadata must belong to its containing entity")
    func indexMetadataMustBelongToContainingEntity() throws {
        let descriptor = try IndexDescriptor(
            name: "owned_index",
            definition: .scalar,
            fields: [SchemaValidationEntity.fields.first.ascending]
        )

        #expect(descriptor.entityName == "SchemaValidationEntity")
        #expect(
            throws: SchemaEntityError.invalidIndexEntity(
                indexName: "owned_index",
                expected: "DifferentEntity",
                actual: "SchemaValidationEntity"
            )
        ) {
            try Schema.Entity(
                name: "DifferentEntity",
                identifierType: .string,
                fields: SchemaValidationEntity.fieldSchemas,
                indexes: [IndexDescriptorMetadata(descriptor)]
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

    @Test("Single array scalar indexes use the ordered element domain")
    func singleArrayScalarIndexesAreAccepted() throws {
        let entity = try ArrayScalarIndexEntity.schemaEntity

        #expect(entity.indexes.map(\.name) == ["tags"])
    }

    @Test("Composite scalar indexes reject implicit array products")
    func compositeScalarIndexesRejectArrays() {
        #expect(
            throws: SchemaEntityError.invalidIndexDeclaration(
                IndexDeclarationError(
                    indexName: "category_tags",
                    validationError: .unsupportedField(
                        index: "scalar",
                        field: FieldSchema(
                            name: "tags",
                            fieldNumber: 3,
                            type: .string,
                            isArray: true
                        ),
                        reason: "Composite scalar indexes require scalar fields with canonical ordering"
                    )
                )
            )
        ) {
            _ = try CompositeArrayScalarIndexEntity.schemaEntity
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

    @Test("Ontology properties must reference declared fields")
    func ontologyPropertiesMustReferenceDeclaredFields() {
        #expect(
            throws: SchemaEntityError.unknownOntologyPropertyField("missing")
        ) {
            try Schema.Entity(
                name: "Entity",
                identifierType: .string,
                fields: [
                    FieldSchema(name: "name", fieldNumber: 1, type: .string)
                ],
                ontology: .owlClass(
                    iri: "urn:Entity",
                    properties: [
                        OWLDataPropertyDescriptor(
                            name: "Entity_missing",
                            fieldName: "missing",
                            iri: "urn:missing"
                        )
                    ]
                )
            )
        }
    }

    @Test("One field has one ontology property mapping")
    func ontologyPropertyFieldMappingsAreUnique() {
        #expect(
            throws: SchemaEntityError.duplicateOntologyPropertyField("name")
        ) {
            try Schema.Entity(
                name: "Entity",
                identifierType: .string,
                fields: [
                    FieldSchema(name: "name", fieldNumber: 1, type: .string)
                ],
                ontology: .owlClass(
                    iri: "urn:Entity",
                    properties: [
                        OWLDataPropertyDescriptor(
                            name: "Entity_name_a",
                            fieldName: "name",
                            iri: "urn:name:a"
                        ),
                        OWLDataPropertyDescriptor(
                            name: "Entity_name_b",
                            fieldName: "name",
                            iri: "urn:name:b"
                        )
                    ]
                )
            )
        }
    }

    @Test("Ontology object-property target metadata must be complete")
    func ontologyPropertyTargetMetadataMustBeComplete() {
        #expect(
            throws: SchemaEntityError.invalidOntologyPropertyTarget("name")
        ) {
            try Schema.Entity(
                name: "Entity",
                identifierType: .string,
                fields: [
                    FieldSchema(name: "name", fieldNumber: 1, type: .string)
                ],
                ontology: .owlClass(
                    iri: "urn:Entity",
                    properties: [
                        OWLDataPropertyDescriptor(
                            name: "Entity_name",
                            fieldName: "name",
                            iri: "urn:name",
                            targetTypeName: "Target",
                            targetFieldName: nil
                        )
                    ]
                )
            )
        }
    }

    @Test("Ontology object properties accept canonical scalar target IDs")
    func ontologyObjectPropertiesAcceptCanonicalScalarTargetIDs() throws {
        let target = try Schema.Entity(
            name: "Target",
            identifierType: .string,
            fields: [
                FieldSchema(name: "id", fieldNumber: 1, type: .string),
            ]
        )
        let source = try Schema.Entity(
            name: "Entity",
            identifierType: .string,
            fields: [
                FieldSchema(name: "id", fieldNumber: 1, type: .string),
                FieldSchema(
                    name: "targetID",
                    fieldNumber: 2,
                    type: .string,
                    isOptional: true
                ),
            ],
            ontology: .owlClass(
                iri: "urn:Entity",
                properties: [
                    OWLDataPropertyDescriptor(
                        name: "Entity_targetID",
                        fieldName: "targetID",
                        iri: "urn:target",
                        targetTypeName: "Target",
                        targetFieldName: "id"
                    ),
                ]
            )
        )

        _ = try Schema(entities: [source, target])
    }
}
