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
        .ordered(
            name: "tags",
            keys: [.ascending(\ArrayScalarIndexEntity.tags)]
        )
    )

    var tags: [String]
}

@Persistable
private struct CompositeArrayScalarIndexEntity {
    var id: String = "fixture-id"
    #Index(
        .ordered(
            name: "category_tags",
            keys: [
                .ascending(\CompositeArrayScalarIndexEntity.category),
                .ascending(\CompositeArrayScalarIndexEntity.tags),
            ]
        )
    )

    var category: String
    var tags: [String]
}

@Persistable
private struct InvalidVectorConfigurationEntity {
    var id: String = "fixture-id"
    #Index(
        .vector(
            name: "invalid_vector",
            embedding: \InvalidVectorConfigurationEntity.embedding,
            dimensions: 0
        )
    )

    var embedding: Vector
}

@Persistable
private struct OptionalScalarIndexEntity {
    var id: String = "fixture-id"
    #Index(
        .ordered(
            name: "optional_scalar",
            keys: [.ascending(\OptionalScalarIndexEntity.value)]
        )
    )

    var value: String?
}

@Suite("Schema Validation")
struct SchemaValidationTests {
    @Test("Field schema distinguishes absent defaults from canonical null")
    func fieldSchemaDefaultIdentity() {
        let required = FieldSchema(
            name: "required",
            fieldNumber: 1,
            type: .string
        )
        let optional = FieldSchema(
            name: "optional",
            fieldNumber: 2,
            type: .string,
            isOptional: true
        )

        #expect(required.defaultValue == nil)
        #expect(optional.defaultValue == .null)
    }

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
            entityName: "FirstIndexedEntity",
            declaration: .ordered(
                name: "duplicate_index",
                keys: [.ascending(SchemaValidationEntity.fields.first.identity)]
            ),
            fieldSchemas: try SchemaValidationEntity.fieldSchemas
        )
        let second = try IndexDescriptor(
            entityName: "SecondIndexedEntity",
            declaration: .ordered(
                name: "duplicate_index",
                keys: [.ascending(SchemaValidationEntity.fields.second.identity)]
            ),
            fieldSchemas: try SchemaValidationEntity.fieldSchemas
        )
        let firstEntity = try Schema.Entity(
            name: "FirstIndexedEntity",
            identifierType: .string,
            fields: try SchemaValidationEntity.fieldSchemas,
            indexes: [
                first
            ]
        )
        let secondEntity = try Schema.Entity(
            name: "SecondIndexedEntity",
            identifierType: .string,
            fields: try SchemaValidationEntity.fieldSchemas,
            indexes: [
                second
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
            entityName: "SchemaValidationEntity",
            declaration: .ordered(
                name: "owned_index",
                keys: [.ascending(SchemaValidationEntity.fields.first.identity)]
            ),
            fieldSchemas: try SchemaValidationEntity.fieldSchemas
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
                fields: try SchemaValidationEntity.fieldSchemas,
                indexes: [descriptor]
            )
        }
    }

    @Test("Changing a named index definition is one replacement")
    func changedNamedIndexIsReplacement() throws {
        let fields = try SchemaValidationEntity.fieldSchemas
        let previousIndex = try IndexDescriptor(
            entityName: "EvolvingIndexEntity",
            declaration: .ordered(
                name: "evolving_index",
                keys: [.ascending(SchemaValidationEntity.fields.first.identity)]
            ),
            fieldSchemas: fields
        )
        let currentIndex = try IndexDescriptor(
            entityName: "EvolvingIndexEntity",
            declaration: .ordered(
                name: "evolving_index",
                keys: [.descending(SchemaValidationEntity.fields.first.identity)]
            ),
            fieldSchemas: fields
        )
        let previous = try Schema(
            entities: [
                Schema.Entity(
                    name: "EvolvingIndexEntity",
                    identifierType: .string,
                    fields: fields,
                    indexes: [previousIndex]
                )
            ],
            version: Schema.Version(1, 0, 0)
        )
        let current = try Schema(
            entities: [
                Schema.Entity(
                    name: "EvolvingIndexEntity",
                    identifierType: .string,
                    fields: fields,
                    indexes: [currentIndex]
                )
            ],
            version: Schema.Version(2, 0, 0)
        )

        #expect(
            current.indexChanges(from: previous) == [
                .replaced(previous: previousIndex, current: currentIndex)
            ]
        )
    }

    @Test("Changing a named polymorphic index is one replacement")
    func changedNamedPolymorphicIndexIsReplacement() throws {
        let previousDeclaration = IndexDeclaration<String>.ordered(
            name: "evolving_polymorphic_index",
            keys: [.ascending("first")]
        )
        let currentDeclaration = IndexDeclaration<String>.ordered(
            name: "evolving_polymorphic_index",
            keys: [.descending("first")]
        )
        let previous = try polymorphicSchema(
            declaration: previousDeclaration,
            version: Schema.Version(1, 0, 0)
        )
        let current = try polymorphicSchema(
            declaration: currentDeclaration,
            version: Schema.Version(2, 0, 0)
        )
        let identity = PolymorphicIndexIdentity(
            groupIdentifier: "EvolvingGroup",
            name: "evolving_polymorphic_index"
        )

        #expect(
            current.polymorphicIndexChanges(from: previous) == [
                .replaced(
                    identity: identity,
                    previous: previousDeclaration,
                    current: currentDeclaration
                )
            ]
        )

        let missingFieldDeclaration = IndexDeclaration<String>.ordered(
            name: "missing_polymorphic_field",
            keys: [.ascending("missing")]
        )
        #expect(throws: SchemaError.self) {
            _ = try polymorphicSchema(
                declaration: missingFieldDeclaration,
                version: Schema.Version(3, 0, 0)
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

    @Test("Ordered indexes reject implicit array expansion")
    func orderedIndexesRejectArrays() {
        #expect(throws: SchemaEntityError.self) {
            _ = try ArrayScalarIndexEntity.schemaEntity
        }
    }

    @Test("Composite scalar indexes reject implicit array products")
    func compositeScalarIndexesRejectArrays() {
        #expect(
            throws: SchemaEntityError.invalidIndexDeclaration(
                IndexDeclarationError(
                    indexName: "category_tags",
                    validationError: .unsupportedField(
                            index: "category_tags",
                        field: FieldSchema(
                            name: "tags",
                            fieldNumber: 3,
                            type: .string,
                            isArray: true
                        ),
                        reason: "Ordered indexes require canonical ordering"
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
                        index: "invalid_vector",
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

    @Test("Ontology projections reject fields the runtime cannot maintain")
    func ontologyProjectionRejectsIncludedFields() {
        let field = FieldSchema(
            name: "first",
            fieldNumber: 1,
            type: .string
        )
        #expect(
            throws: IndexDeclarationError(
                indexName: "ontology_projection",
                validationError: .invalidConfiguration(
                    index: "ontology_projection",
                    reason: "Ontology projection requires an IRI base and no fields"
                )
            )
        ) {
            try IndexDescriptor(
                entityName: "OntologyProjectionEntity",
                declaration: .graph(
                    name: "ontology_projection",
                    definition: .ontologyProjection(
                        individualIRIBase: "urn:entity:",
                        graph: nil
                    ),
                    includedFields: [
                        FieldIdentity(
                            name: field.name,
                            number: field.fieldNumber
                        )
                    ]
                ),
                fieldSchemas: [field]
            )
        }
    }

    @Test("Descriptor field identities must match the static schema")
    func descriptorFieldIdentitiesMustMatchSchema() {
        #expect(
            throws: IndexDeclarationError(
                indexName: "mismatched_descriptor",
                validationError: .invalidConfiguration(
                    index: "mismatched_descriptor",
                    reason: "Field identity 'first#3' is absent from the entity schema"
                )
            )
        ) {
            try IndexDescriptor(
                entityName: "SchemaValidationEntity",
                declaration: .ordered(
                    name: "mismatched_descriptor",
                    keys: [.ascending(
                        FieldIdentity(name: "first", number: 3)
                    )]
                ),
                fieldSchemas: try SchemaValidationEntity.fieldSchemas
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

    private func polymorphicSchema(
        declaration: IndexDeclaration<String>,
        version: Schema.Version
    ) throws -> Schema {
        try Schema(
            entities: [
                Schema.Entity(
                    name: "EvolvingPolymorphicEntity",
                    identifierType: .string,
                    fields: try SchemaValidationEntity.fieldSchemas,
                    polymorphicMembership: PolymorphicMembership(
                        identifier: "EvolvingGroup",
                        directoryComponents: [
                            .staticPath("evolving-polymorphic")
                        ],
                        directoryLayer: .default,
                        indexes: [declaration]
                    )
                )
            ],
            version: version
        )
    }
}

@Suite("Directory Declaration Validation")
struct DirectoryDeclarationValidationTests {
    private static let identifier = FieldSchema(
        name: "id",
        fieldNumber: 1,
        type: .string
    )

    private static let tenant = FieldSchema(
        name: "tenantID",
        fieldNumber: 2,
        type: .string
    )

    private static func entity(
        name: String = "DirectoryDeclaration",
        fields: [FieldSchema],
        components: [DirectoryPathComponent],
        layer: DirectoryLayer = .default,
        membership: PolymorphicMembership? = nil
    ) throws(SchemaEntityError) -> Schema.Entity {
        try Schema.Entity(
            name: name,
            identifierType: .string,
            fields: [identifier] + fields,
            directoryComponents: components,
            directoryLayer: layer,
            polymorphicMembership: membership
        )
    }

    private static func membership(
        layer: DirectoryLayer
    ) -> PolymorphicMembership {
        PolymorphicMembership(
            identifier: "Shape",
            directoryComponents: [.staticPath("shapes")],
            directoryLayer: layer,
            indexes: []
        )
    }

    @Test("A required scalar dynamic component resolves a partition leaf")
    func requiredScalarDynamicComponentIsAccepted() throws {
        let entity = try Self.entity(
            fields: [Self.tenant],
            components: [.staticPath("tenants"), .dynamicField(fieldName: "tenantID")],
            layer: .partition
        )
        #expect(
            entity.directoryComponents == [
                .staticPath("tenants"),
                .dynamicField(fieldName: "tenantID"),
            ]
        )
        #expect(entity.directoryLayer == .partition)
    }

    @Test("A partition leaf requires at least one dynamic component")
    func staticOnlyPartitionDeclarationIsRejected() {
        #expect(throws: SchemaEntityError.partitionDirectoryRequiresDynamicField) {
            try Self.entity(
                fields: [Self.tenant],
                components: [.staticPath("tenants")],
                layer: .partition
            )
        }
    }

    @Test("An optional field cannot resolve a dynamic component")
    func optionalDynamicComponentIsRejected() {
        let optionalTenant = FieldSchema(
            name: "tenantID",
            fieldNumber: 2,
            type: .string,
            isOptional: true
        )
        #expect(throws: SchemaEntityError.optionalDirectoryField("tenantID")) {
            try Self.entity(
                fields: [optionalTenant],
                components: [.dynamicField(fieldName: "tenantID")]
            )
        }
    }

    @Test("An array field cannot resolve a dynamic component")
    func arrayDynamicComponentIsRejected() {
        let tags = FieldSchema(
            name: "tags",
            fieldNumber: 2,
            type: .string,
            isArray: true
        )
        #expect(
            throws: SchemaEntityError.arrayDirectoryField(fieldName: "tags")
        ) {
            try Self.entity(
                fields: [tags],
                components: [.dynamicField(fieldName: "tags")]
            )
        }
    }

    @Test("A nested field cannot resolve a dynamic component")
    func nestedDynamicComponentIsRejected() {
        let profile = FieldSchema(
            name: "profile",
            fieldNumber: 2,
            type: .nested
        )
        #expect(
            throws: SchemaEntityError.unsupportedDirectoryFieldKind(
                fieldName: "profile",
                type: .nested
            )
        ) {
            try Self.entity(
                fields: [profile],
                components: [.dynamicField(fieldName: "profile")]
            )
        }
    }

    @Test("An object field cannot resolve a dynamic component")
    func objectDynamicComponentIsRejected() {
        let payload = FieldSchema(
            name: "payload",
            fieldNumber: 2,
            type: .object
        )
        #expect(
            throws: SchemaEntityError.unsupportedDirectoryFieldKind(
                fieldName: "payload",
                type: .object
            )
        ) {
            try Self.entity(
                fields: [payload],
                components: [.dynamicField(fieldName: "payload")]
            )
        }
    }

    @Test("A vector field cannot resolve a dynamic component")
    func vectorDynamicComponentIsRejected() {
        let embedding = FieldSchema(
            name: "embedding",
            fieldNumber: 2,
            type: .vector
        )
        #expect(
            throws: SchemaEntityError.unsupportedDirectoryFieldKind(
                fieldName: "embedding",
                type: .vector
            )
        ) {
            try Self.entity(
                fields: [embedding],
                components: [.dynamicField(fieldName: "embedding")]
            )
        }
    }

    @Test("An RDF term field cannot resolve a dynamic component")
    func rdfTermDynamicComponentIsRejected() {
        let subject = FieldSchema(
            name: "subject",
            fieldNumber: 2,
            type: .rdfTerm
        )
        #expect(
            throws: SchemaEntityError.unsupportedDirectoryFieldKind(
                fieldName: "subject",
                type: .rdfTerm
            )
        ) {
            try Self.entity(
                fields: [subject],
                components: [.dynamicField(fieldName: "subject")]
            )
        }
    }

    @Test("A reference field cannot resolve a dynamic component")
    func referenceDynamicComponentIsRejected() {
        let owner = FieldSchema(
            name: "owner",
            fieldNumber: 2,
            type: .reference,
            referenceTargetEntity: "Account"
        )
        #expect(
            throws: SchemaEntityError.unsupportedDirectoryFieldKind(
                fieldName: "owner",
                type: .reference
            )
        ) {
            try Self.entity(
                fields: [owner],
                components: [.dynamicField(fieldName: "owner")]
            )
        }
    }

    @Test("A polymorphic membership path admits no dynamic component")
    func polymorphicMembershipDynamicComponentIsRejected() {
        let group = PolymorphicMembership(
            identifier: "Shape",
            directoryComponents: [
                .staticPath("shapes"),
                .dynamicField(fieldName: "tenantID"),
            ],
            directoryLayer: .default,
            indexes: []
        )
        #expect(
            throws: SchemaEntityError.invalidPolymorphicDirectoryComponent(
                position: 1
            )
        ) {
            try Self.entity(
                fields: [Self.tenant],
                components: [.staticPath("records")],
                membership: group
            )
        }
    }

    @Test("A dynamic component field occurs at most once in a declaration")
    func repeatedDynamicComponentIsRejected() {
        #expect(throws: SchemaEntityError.duplicateDirectoryField("tenantID")) {
            try Self.entity(
                fields: [Self.tenant],
                components: [
                    .dynamicField(fieldName: "tenantID"),
                    .staticPath("records"),
                    .dynamicField(fieldName: "tenantID"),
                ]
            )
        }
    }

    @Test("A polymorphic declaration retains its declared leaf layer tag")
    func polymorphicPartitionDeclarationRetainsLayerTag() throws {
        let entity = try Self.entity(
            fields: [Self.tenant],
            components: [],
            membership: Self.membership(layer: .partition)
        )
        #expect(entity.polymorphicMembership?.directoryLayer == .partition)
    }

    @Test("A polymorphic declaration resolves a plain directory leaf")
    func polymorphicDefaultDeclarationIsAccepted() throws {
        let entity = try Self.entity(
            fields: [Self.tenant],
            components: [],
            membership: Self.membership(layer: .default)
        )
        #expect(entity.polymorphicMembership?.directoryLayer == .default)
    }

    @Test("Members agreeing on the leaf layer tag share one polymorphic node")
    func agreeingPolymorphicLayerTagIsAccepted() throws {
        let schema = try Schema(
            entities: [
                Self.entity(
                    name: "Circle",
                    fields: [Self.tenant],
                    components: [],
                    membership: Self.membership(layer: .partition)
                ),
                Self.entity(
                    name: "Square",
                    fields: [Self.tenant],
                    components: [],
                    membership: Self.membership(layer: .partition)
                ),
            ]
        )
        let group = try #require(
            schema.polymorphicGroups.first { $0.identifier == "Shape" }
        )
        #expect(group.directoryLayer == .partition)
        #expect(group.directoryComponents == [.staticPath("shapes")])
    }

    @Test("Members disagreeing on the leaf layer tag are a typed schema error")
    func disagreeingPolymorphicLayerTagIsRejected() throws {
        let circle = try Self.entity(
            name: "Circle",
            fields: [Self.tenant],
            components: [],
            membership: Self.membership(layer: .default)
        )
        let square = try Self.entity(
            name: "Square",
            fields: [Self.tenant],
            components: [],
            membership: Self.membership(layer: .partition)
        )
        #expect(
            throws: SchemaError.inconsistentPolymorphicDirectoryLayer(group: "Shape")
        ) {
            try Schema(entities: [circle, square])
        }
    }
}
