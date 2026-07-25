/// A logical index shared by every concrete member of a polymorphic group.
///
/// Protocol declarations own field names because field numbers belong to each
/// concrete persisted schema. `Schema` resolves these selections into stable
/// `FieldIdentity` values before exposing an index catalog to the runtime.
public struct PolymorphicIndexDefinition: Sendable, Hashable {
    public let name: String
    public let definition: IndexDefinition
    public let fields: [PolymorphicIndexField]
    public let commonOptions: CommonIndexOptions
    public let storedFieldNames: [String]

    public init(
        name: String,
        definition: IndexDefinition,
        fields: [PolymorphicIndexField],
        commonOptions: CommonIndexOptions = .init(),
        storedFieldNames: [String] = []
    ) {
        self.name = name
        self.definition = definition
        self.fields = fields
        self.commonOptions = commonOptions
        self.storedFieldNames = storedFieldNames
    }

    package func descriptor(
        fieldSchemas: [FieldSchema]
    ) throws(IndexDeclarationError) -> IndexDescriptor {
        var schemasByName: [String: FieldSchema] = [:]
        for schema in fieldSchemas {
            schemasByName[schema.name] = schema
        }

        var resolvedFields: [IndexFieldMetadata] = []
        var resolvedSchemas: [FieldSchema] = []
        resolvedFields.reserveCapacity(fields.count)
        resolvedSchemas.reserveCapacity(fields.count)
        for field in fields {
            guard let schema = schemasByName[field.name] else {
                throw IndexDeclarationError(
                    indexName: name,
                    validationError: .invalidConfiguration(
                        index: definition.identifier,
                        reason: "Field '\(field.name)' is absent from a concrete member schema"
                    )
                )
            }
            resolvedFields.append(
                IndexFieldMetadata(
                    identity: FieldIdentity(
                        name: schema.name,
                        number: schema.fieldNumber
                    ),
                    order: field.order
                )
            )
            resolvedSchemas.append(schema)
        }

        for storedFieldName in storedFieldNames
        where schemasByName[storedFieldName] == nil {
            throw IndexDeclarationError(
                indexName: name,
                validationError: .invalidConfiguration(
                    index: definition.identifier,
                    reason: "Stored field '\(storedFieldName)' is absent from a concrete member schema"
                )
            )
        }

        do {
            let kind = try definition.kindMetadata(
                fields: resolvedFields,
                schemas: resolvedSchemas
            )
            return IndexDescriptor(
                validatedMetadata: IndexDescriptorMetadata(
                    name: name,
                    kind: kind,
                    commonOptions: commonOptions,
                    storedFieldNames: storedFieldNames
                )
            )
        } catch let validationError {
            throw IndexDeclarationError(
                indexName: name,
                validationError: validationError
            )
        }
    }
}
