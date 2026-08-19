/// A stable, explicitly named logical index declaration.
public struct IndexDeclaration<FieldReference> {
    public let name: String
    public let definition: IndexDefinition<FieldReference>

    public init(
        name: String,
        definition: IndexDefinition<FieldReference>
    ) {
        self.name = name
        self.definition = definition
    }

    public func mapFields<NewFieldReference, Failure: Error>(
        _ transform: (FieldReference) throws(Failure) -> NewFieldReference
    ) throws(Failure) -> IndexDeclaration<NewFieldReference> {
        IndexDeclaration<NewFieldReference>(
            name: name,
            definition: try definition.mapFields(transform)
        )
    }

    public var type: IndexType { definition.type }
    public var keys: [IndexKey<FieldReference>] { definition.keys }
    public var fieldReferences: [FieldReference] {
        keys.map { $0.field }
    }
    public var includedFields: [FieldReference] {
        definition.includedFields
    }
    public var isUnique: Bool { definition.isUnique }
}

extension IndexDeclaration: Sendable where FieldReference: Sendable {}
extension IndexDeclaration: Equatable where FieldReference: Equatable {}
extension IndexDeclaration: Hashable where FieldReference: Hashable {}

extension IndexDeclaration {
    public static func ordered(
        name: String,
        keys: [IndexKey<FieldReference>],
        includedFields: [FieldReference] = [],
        unique: Bool = false
    ) -> Self {
        Self(
            name: name,
            definition: .ordered(
                keys: keys,
                includedFields: includedFields,
                unique: unique
            )
        )
    }

    public static func aggregate(
        name: String,
        function: AggregateIndexFunction,
        groupBy: [IndexKey<FieldReference>] = [],
        value: FieldReference? = nil
    ) -> Self {
        Self(
            name: name,
            definition: .aggregate(
                function: function,
                groupBy: groupBy,
                value: value
            )
        )
    }

    public static func updateCount(name: String, field: FieldReference) -> Self {
        Self(name: name, definition: .updateCount(field: field))
    }

    public static func history(
        name: String,
        version: FieldReference,
        retention: VersionHistoryStrategy = .keepAll
    ) -> Self {
        Self(
            name: name,
            definition: .history(version: version, retention: retention)
        )
    }

    public static func bitmap(name: String, field: FieldReference) -> Self {
        Self(name: name, definition: .bitmap(field: field))
    }

    public static func leaderboard(
        name: String,
        groupBy: [IndexKey<FieldReference>] = [],
        score: FieldReference,
        window: LeaderboardWindowType = .daily,
        windowCount: Int = 7
    ) -> Self {
        Self(
            name: name,
            definition: .leaderboard(
                groupBy: groupBy,
                score: score,
                window: window,
                windowCount: windowCount
            )
        )
    }

    public static func vector(
        name: String,
        embedding: FieldReference,
        dimensions: Int,
        metric: VectorMetric = .cosine
    ) -> Self {
        Self(
            name: name,
            definition: .vector(
                embedding: embedding,
                dimensions: dimensions,
                metric: metric
            )
        )
    }

    public static func text(
        name: String,
        fields: [FieldReference],
        mode: TextIndexMode
    ) -> Self {
        Self(name: name, definition: .text(fields: fields, mode: mode))
    }

    public static func spatial(
        name: String,
        location: FieldReference,
        encoding: SpatialEncoding = .s2,
        level: Int = 15
    ) -> Self {
        Self(
            name: name,
            definition: .spatial(
                location: location,
                encoding: encoding,
                level: level
            )
        )
    }

    public static func rank(name: String, score: FieldReference) -> Self {
        Self(name: name, definition: .rank(score: score))
    }

    public static func graph(
        name: String,
        definition: GraphIndexDefinition<FieldReference>,
        includedFields: [FieldReference] = []
    ) -> Self {
        Self(
            name: name,
            definition: .graph(
                definition,
                includedFields: includedFields
            )
        )
    }

    public static func custom(
        name: String,
        definition: CustomIndexDefinition<FieldReference>
    ) -> Self {
        Self(name: name, definition: .custom(definition))
    }
}

extension IndexDeclaration where FieldReference == String {
    public var fieldNames: [String] { fieldReferences }

    package func descriptor(
        entityName: String,
        fieldSchemas: [FieldSchema]
    ) throws(IndexDeclarationError) -> IndexDescriptor {
        var schemasByName: [String: FieldSchema] = [:]
        schemasByName.reserveCapacity(fieldSchemas.count)
        for schema in fieldSchemas {
            schemasByName[schema.name] = schema
        }
        let resolved: IndexDeclaration<FieldIdentity>
        do {
            resolved = try mapFields { name throws(IndexValidationError) in
                guard let schema = schemasByName[name] else {
                    throw .invalidConfiguration(
                        index: self.name,
                        reason: "Field '\(name)' is absent from a concrete member schema"
                    )
                }
                return FieldIdentity(
                    name: schema.name,
                    number: schema.fieldNumber
                )
            }
        } catch let validationError {
            throw IndexDeclarationError(
                indexName: name,
                validationError: validationError
            )
        }
        return try IndexDescriptor(
            entityName: entityName,
            declaration: resolved,
            fieldSchemas: fieldSchemas
        )
    }
}
