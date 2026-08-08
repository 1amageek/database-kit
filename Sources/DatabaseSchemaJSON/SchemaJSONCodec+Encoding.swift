import DatabaseKit
import DatabaseWire

extension SchemaJSONCodec {
    func encodeManifest(_ manifest: SchemaManifest) throws -> JSONValue {
        .object([
            ("formatVersion", .number(String(manifest.formatVersion))),
            ("schemaVersion", encodeVersion(manifest.schema.version)),
            (
                "entities",
                .array(
                    try manifest.schema.entities
                        .sorted { $0.name < $1.name }
                        .map(encodeEntity)
                )
            ),
        ])
    }

    private func encodeVersion(_ version: SchemaVersion) -> JSONValue {
        .object([
            ("major", .number(String(version.major))),
            ("minor", .number(String(version.minor))),
            ("patch", .number(String(version.patch))),
        ])
    }

    private func encodeEntity(_ entity: Schema.Entity) throws -> JSONValue {
        .object([
            ("name", .string(entity.name)),
            ("identifierType", encodeIdentifierType(entity.identifierType)),
            (
                "fields",
                .array(
                    entity.fields
                        .sorted { ($0.fieldNumber, $0.name) < ($1.fieldNumber, $1.name) }
                        .map(encodeField)
                )
            ),
            (
                "directory",
                encodeDirectory(
                    entity.directoryComponents,
                    layer: entity.directoryLayer
                )
            ),
            (
                "indexes",
                .array(try entity.indexes.sorted { $0.name < $1.name }.map(encodeIndex))
            ),
            (
                "relationships",
                .array(
                    entity.relationships
                        .sorted {
                            ($0.propertyFieldNumber, $0.propertyName)
                                < ($1.propertyFieldNumber, $1.propertyName)
                        }
                        .map(encodeRelationship)
                )
            ),
            (
                "fieldAccessRules",
                .array(
                    entity.fieldAccessRules
                        .sorted {
                            ($0.field.number, $0.field.name)
                                < ($1.field.number, $1.field.name)
                        }
                        .map(encodeAccessRule)
                )
            ),
            ("enumMetadata", encodeStringArrayMap(entity.enumMetadata)),
            ("ontology", encodeOntology(entity.ontology)),
            (
                "polymorphicMembership",
                try encodePolymorphicMembership(entity.polymorphicMembership)
            ),
        ])
    }

    private func encodeIdentifierType(
        _ value: PersistableIdentifierType
    ) -> JSONValue {
        switch value {
        case .bool: return kind("bool")
        case .int8: return kind("int8")
        case .int16: return kind("int16")
        case .int32: return kind("int32")
        case .int64: return kind("int64")
        case .uint8: return kind("uint8")
        case .uint16: return kind("uint16")
        case .uint32: return kind("uint32")
        case .uint64: return kind("uint64")
        case .string: return kind("string")
        case .bytes: return kind("bytes")
        case .uuid: return kind("uuid")
        case .composite(let components):
            return .object([
                ("kind", .string("composite")),
                ("components", .array(components.map(encodeIdentifierType))),
            ])
        }
    }

    private func encodeField(_ field: FieldSchema) -> JSONValue {
        .object([
            ("name", .string(field.name)),
            ("number", .number(String(field.fieldNumber))),
            ("type", .string(field.type.rawValue)),
            ("optional", .bool(field.isOptional)),
            ("array", .bool(field.isArray)),
            ("referenceTargetEntity", optionalString(field.referenceTargetEntity)),
        ])
    }

    private func encodeDirectory(
        _ components: [DirectoryPathComponent],
        layer: DirectoryLayer
    ) -> JSONValue {
        .object([
            (
                "components",
                .array(components.map { component in
                    switch component {
                    case .staticPath(let value):
                        .object([
                            ("kind", .string("static")),
                            ("value", .string(value)),
                        ])
                    case .dynamicField(let fieldName):
                        .object([
                            ("kind", .string("field")),
                            ("value", .string(fieldName)),
                        ])
                    }
                })
            ),
            ("layer", .string(layer.rawValue)),
        ])
    }

    private func encodeIndex(_ index: IndexDescriptorMetadata) throws -> JSONValue {
        .object([
            ("entity", .string(index.entityName)),
            ("name", .string(index.name)),
            (
                "kind",
                .object([
                    ("identifier", .string(index.kind.identifier)),
                    ("subspace", .string(index.kind.subspaceStructure.rawValue)),
                    (
                        "fields",
                        .array(index.kind.fields.map(encodeIndexField))
                    ),
                    (
                        "metadata",
                        try encodeFieldValueMap(index.kind.metadata)
                    ),
                ])
            ),
            ("options", encodeCommonOptions(index.commonOptions)),
            ("storedFields", .array(index.storedFieldNames.map(JSONValue.string))),
        ])
    }

    private func encodeIndexField(_ field: IndexFieldMetadata) -> JSONValue {
        .object([
            ("name", .string(field.identity.name)),
            ("number", .number(String(field.identity.number))),
            ("order", .string(field.order.rawValue)),
        ])
    }

    private func encodeCommonOptions(_ options: CommonIndexOptions) -> JSONValue {
        .object([
            ("unique", .bool(options.unique)),
            ("sparse", .bool(options.sparse)),
            ("metadata", encodeStringMap(options.metadata)),
        ])
    }

    private func encodeRelationship(_ value: RelationshipDescriptor) -> JSONValue {
        .object([
            ("ownerEntity", .string(value.ownerTypeName)),
            ("property", .string(value.propertyName)),
            ("fieldNumber", .number(String(value.propertyFieldNumber))),
            ("relatedEntity", .string(value.relatedTypeName)),
            ("cardinality", .string(value.cardinality.rawValue)),
            ("deleteRule", .string(value.deleteRule.rawValue)),
        ])
    }

    private func encodeAccessRule(_ value: FieldAccessRule) -> JSONValue {
        .object([
            ("field", encodeFieldIdentity(value.field)),
            ("read", encodeAccessLevel(value.read)),
            ("write", encodeAccessLevel(value.write)),
        ])
    }

    private func encodeFieldIdentity(_ value: FieldIdentity) -> JSONValue {
        .object([
            ("name", .string(value.name)),
            ("number", .number(String(value.number))),
        ])
    }

    private func encodeAccessLevel(_ value: FieldAccessLevel) -> JSONValue {
        switch value {
        case .public: return kind("public")
        case .authenticated: return kind("authenticated")
        case .roles(let roles):
            return .object([
                ("kind", .string("roles")),
                ("roles", .array(roles.sorted().map(JSONValue.string))),
            ])
        }
    }

    private func encodeOntology(_ value: OntologyBinding?) -> JSONValue {
        guard let value else { return .null }
        switch value {
        case .owlClass(let iri, let properties):
            return .object([
                ("kind", .string("owlClass")),
                ("iri", .string(iri)),
                ("properties", .array(properties.map(encodeOntologyProperty))),
            ])
        case .owlObjectProperty(let iri, let fromField, let toField, let properties):
            return .object([
                ("kind", .string("owlObjectProperty")),
                ("iri", .string(iri)),
                ("fromField", .string(fromField)),
                ("toField", .string(toField)),
                ("properties", .array(properties.map(encodeOntologyProperty))),
            ])
        }
    }

    private func encodeOntologyProperty(
        _ value: OWLDataPropertyDescriptor
    ) -> JSONValue {
        .object([
            ("name", .string(value.name)),
            ("field", .string(value.fieldName)),
            ("iri", .string(value.iri)),
            ("label", optionalString(value.label)),
            ("targetEntity", optionalString(value.targetTypeName)),
            ("targetField", optionalString(value.targetFieldName)),
        ])
    }

    private func encodePolymorphicMembership(
        _ value: PolymorphicMembership?
    ) throws -> JSONValue {
        guard let value else { return .null }
        return .object([
            ("identifier", .string(value.identifier)),
            (
                "directory",
                encodeDirectory(value.directoryComponents, layer: value.directoryLayer)
            ),
            (
                "indexes",
                .array(try value.indexes.map(encodePolymorphicIndex))
            ),
        ])
    }

    private func encodePolymorphicIndex(
        _ value: PolymorphicIndexDefinition
    ) throws -> JSONValue {
        .object([
            ("name", .string(value.name)),
            ("definition", try encodeIndexDefinition(value.definition)),
            (
                "fields",
                .array(value.fields.map { field in
                    .object([
                        ("name", .string(field.name)),
                        ("order", .string(field.order.rawValue)),
                    ])
                })
            ),
            ("options", encodeCommonOptions(value.commonOptions)),
            ("storedFields", .array(value.storedFieldNames.map(JSONValue.string))),
        ])
    }

    private func encodeFieldValueMap(
        _ values: [String: DatabaseTypes.FieldValue]
    ) throws -> JSONValue {
        .object(
            try values.keys.sorted().map { key in
                guard let value = values[key] else {
                    throw SchemaJSONError.invalidValue(
                        path: "index.kind.metadata.\(key)",
                        reason: "value disappeared while encoding"
                    )
                }
                return (key, try fieldValueCodec.encode(value))
            }
        )
    }

    private func encodeStringMap(_ values: [String: String]) -> JSONValue {
        .object(values.keys.sorted().compactMap { key in
            values[key].map { (key, .string($0)) }
        })
    }

    private func encodeStringArrayMap(_ values: [String: [String]]) -> JSONValue {
        .object(values.keys.sorted().compactMap { key in
            values[key].map { (key, .array($0.map(JSONValue.string))) }
        })
    }

    private func optionalString(_ value: String?) -> JSONValue {
        value.map(JSONValue.string) ?? .null
    }

    private func kind(_ name: String) -> JSONValue {
        .object([("kind", .string(name))])
    }
}
