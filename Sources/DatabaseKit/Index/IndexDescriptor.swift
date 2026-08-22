/// Validated, key-path-free index metadata retained by a schema.
public struct IndexDescriptor: Descriptor, Sendable, Hashable {
    public let entityName: String
    public let declaration: IndexDeclaration<FieldIdentity>
    public let fieldSchemas: [FieldSchema]

    public init(
        entityName: String,
        declaration: IndexDeclaration<FieldIdentity>,
        fieldSchemas: [FieldSchema]
    ) throws(IndexDeclarationError) {
        do {
            try declaration.validate(fieldSchemas: fieldSchemas)
        } catch let error {
            throw IndexDeclarationError(
                indexName: declaration.name,
                validationError: error
            )
        }
        self.entityName = entityName
        self.declaration = declaration
        var schemasByIdentity: [FieldIdentity: FieldSchema] = [:]
        schemasByIdentity.reserveCapacity(fieldSchemas.count)
        for schema in fieldSchemas {
            let identity = FieldIdentity(
                name: schema.name,
                number: schema.fieldNumber
            )
            guard schemasByIdentity.updateValue(
                schema,
                forKey: identity
            ) == nil else {
                throw IndexDeclarationError(
                    indexName: declaration.name,
                    validationError: .invalidConfiguration(
                        index: declaration.name,
                        reason: "Entity field schemas contain the duplicate identity '\(schema.name)#\(schema.fieldNumber)'"
                    )
                )
            }
        }
        self.fieldSchemas = declaration.definition.keys.compactMap {
            schemasByIdentity[$0.field]
        } + declaration.definition.includedFields.compactMap {
            schemasByIdentity[$0]
        }
    }

    public var identity: IndexIdentity {
        IndexIdentity(entityName: entityName, name: name)
    }

    public var name: String {
        declaration.name
    }

    public var type: IndexType {
        declaration.definition.type
    }

    public var keys: [IndexKey<FieldIdentity>] {
        declaration.definition.keys
    }

    public var fieldIdentities: [FieldIdentity] {
        keys.map { $0.field }
    }

    public var fieldNames: [String] {
        fieldIdentities.map { $0.name }
    }

    public var keyFieldSchemas: [FieldSchema] {
        Array(fieldSchemas.prefix(keys.count))
    }

    public var includedFieldIdentities: [FieldIdentity] {
        declaration.definition.includedFields
    }

    public var includedFieldNames: [String] {
        includedFieldIdentities.map { $0.name }
    }

    public var isUnique: Bool {
        declaration.definition.isUnique
    }

    public var isCovering: Bool {
        !includedFieldIdentities.isEmpty
    }
}

extension IndexDescriptor: CustomStringConvertible {
    public var description: String {
        "IndexDescriptor(entity: \(entityName), name: \(name), type: \(type.diagnosticName), fields: [\(fieldNames.joined(separator: ", "))])"
    }
}

extension IndexDeclaration where FieldReference == FieldIdentity {
    package func validate(
        fieldSchemas: [FieldSchema]
    ) throws(IndexValidationError) {
        guard !name.isEmpty else {
            throw .invalidConfiguration(
                index: name,
                reason: "Index name must not be empty"
            )
        }

        var fieldsByNumber: [Int: FieldSchema] = [:]
        fieldsByNumber.reserveCapacity(fieldSchemas.count)
        var fieldNames = Set<String>()
        for field in fieldSchemas {
            guard fieldNames.insert(field.name).inserted else {
                throw .invalidConfiguration(
                    index: name,
                    reason: "Entity field schemas contain the duplicate name '\(field.name)'"
                )
            }
            guard fieldsByNumber.updateValue(
                field,
                forKey: field.fieldNumber
            ) == nil else {
                throw .invalidConfiguration(
                    index: name,
                    reason: "Entity field schemas contain the duplicate number '\(field.fieldNumber)'"
                )
            }
        }

        func schema(for identity: FieldIdentity) throws(IndexValidationError) -> FieldSchema {
            guard let schema = fieldsByNumber[identity.number],
                  schema.name == identity.name else {
                throw .invalidConfiguration(
                    index: name,
                    reason: "Field identity '\(identity.name)#\(identity.number)' is absent from the entity schema"
                )
            }
            return schema
        }

        var keySchemas: [FieldSchema] = []
        keySchemas.reserveCapacity(definition.keys.count)
        var keyIdentities = Set<FieldIdentity>()
        for key in definition.keys {
            guard keyIdentities.insert(key.field).inserted else {
                throw .invalidConfiguration(
                    index: name,
                    reason: "A key field may appear only once"
                )
            }
            keySchemas.append(try schema(for: key.field))
        }

        var includedIdentities = Set<FieldIdentity>()
        for field in definition.includedFields {
            _ = try schema(for: field)
            guard includedIdentities.insert(field).inserted else {
                throw .invalidConfiguration(
                    index: name,
                    reason: "An included field may appear only once"
                )
            }
            guard !keyIdentities.contains(field) else {
                throw .invalidConfiguration(
                    index: name,
                    reason: "A key field must not be repeated as an included field"
                )
            }
        }

        try definition.validate(schemas: keySchemas, indexName: name)
    }
}

extension IndexDefinition where FieldReference == FieldIdentity {
    fileprivate func validate(
        schemas: [FieldSchema],
        indexName: String
    ) throws(IndexValidationError) {
        func requireCount(_ expected: Int) throws(IndexValidationError) {
            guard schemas.count == expected else {
                throw .invalidFieldCount(
                    index: indexName,
                    expected: expected,
                    actual: schemas.count
                )
            }
        }

        func requireMinimumCount(_ minimum: Int) throws(IndexValidationError) {
            guard schemas.count >= minimum else {
                throw .invalidFieldCount(
                    index: indexName,
                    expected: minimum,
                    actual: schemas.count
                )
            }
        }

        func requireOrdered(
            _ fields: some Sequence<FieldSchema>,
            reason: String
        ) throws(IndexValidationError) {
            for field in fields where !field.supportsOrderedIndex {
                throw .unsupportedField(
                    index: indexName,
                    field: field,
                    reason: reason
                )
            }
        }

        func requireNumeric(
            _ field: FieldSchema,
            reason: String
        ) throws(IndexValidationError) {
            guard field.indexScalarType?.isNumeric == true else {
                throw .unsupportedField(
                    index: indexName,
                    field: field,
                    reason: reason
                )
            }
        }

        switch self {
        case .ordered:
            try requireMinimumCount(1)
            try requireOrdered(
                schemas,
                reason: "Ordered indexes require canonical ordering"
            )

        case .aggregate(let function, let groupBy, let value):
            let groupCount = groupBy.count
            try requireOrdered(
                schemas.prefix(groupCount),
                reason: "Aggregation grouping fields require canonical ordering"
            )
            switch function {
            case .count:
                guard value == nil else {
                    throw .invalidConfiguration(
                        index: indexName,
                        reason: "Count aggregation does not accept a value field"
                    )
                }
            case .sum, .average, .percentile:
                guard value != nil, schemas.count == groupCount + 1,
                      let valueSchema = schemas.last else {
                    throw .invalidFieldCount(
                        index: indexName,
                        expected: groupCount + 1,
                        actual: schemas.count
                    )
                }
                try requireNumeric(
                    valueSchema,
                    reason: "Aggregation value must be numeric"
                )
                if case .percentile(let compression) = function {
                    guard compression.isFinite,
                          (1...1_000).contains(compression) else {
                        throw .invalidConfiguration(
                            index: indexName,
                            reason: "Percentile compression must be finite and in 1...1000"
                        )
                    }
                }
            case .minimum, .maximum:
                guard value != nil, schemas.count == groupCount + 1,
                      let valueSchema = schemas.last,
                      valueSchema.indexScalarType != nil else {
                    throw .invalidConfiguration(
                        index: indexName,
                        reason: "Minimum and maximum require one ordered scalar value"
                    )
                }
            case .nonNullCount:
                guard value != nil, schemas.count == groupCount + 1 else {
                    throw .invalidFieldCount(
                        index: indexName,
                        expected: groupCount + 1,
                        actual: schemas.count
                    )
                }
            case .approximateDistinct(let precision):
                guard value != nil, schemas.count == groupCount + 1,
                      let valueSchema = schemas.last,
                      valueSchema.supportsEqualityIndex else {
                    throw .invalidConfiguration(
                        index: indexName,
                        reason: "Approximate distinct requires one equality-comparable value"
                    )
                }
                guard (4...17).contains(precision) else {
                    throw .invalidConfiguration(
                        index: indexName,
                        reason: "Approximate-distinct precision must be in 4...17"
                    )
                }
            }

        case .updateCount:
            try requireCount(1)

        case .history(_, let retention):
            try requireCount(1)
            switch retention {
            case .keepAll:
                break
            case .keepLast(let count):
                guard count > 0 else {
                    throw .invalidConfiguration(
                        index: indexName,
                        reason: "Retained version count must be positive"
                    )
                }
            case .keepForDuration(let duration):
                guard duration.seconds > 0
                        || (duration.seconds == 0 && duration.nanoseconds > 0)
                else {
                    throw .invalidConfiguration(
                        index: indexName,
                        reason: "Retention duration must be positive"
                    )
                }
            }

        case .bitmap:
            try requireCount(1)
            if let field = schemas.first, !field.supportsEqualityIndex {
                throw .unsupportedField(
                    index: indexName,
                    field: field,
                    reason: "Bitmap indexes require a scalar equality value"
                )
            }

        case .leaderboard(let groupBy, _, let window, let windowCount):
            try requireMinimumCount(1)
            guard windowCount > 0,
                  let durationSeconds = Int64(
                    exactly: window.durationSeconds
                  ),
                  durationSeconds > 0 else {
                throw .invalidConfiguration(
                    index: indexName,
                    reason: "Leaderboard windows require a positive whole-second duration representable by Int64 and a positive count"
                )
            }
            try requireOrdered(
                schemas.prefix(groupBy.count),
                reason: "Leaderboard grouping fields require canonical ordering"
            )
            if let score = schemas.last,
               score.type != .int64 || score.isArray {
                throw .unsupportedField(
                    index: indexName,
                    field: score,
                    reason: "Leaderboard score must be Int64"
                )
            }

        case .vector(_, let dimensions, _):
            try requireCount(1)
            guard dimensions > 0 else {
                throw .invalidConfiguration(
                    index: indexName,
                    reason: "Vector dimensions must be positive"
                )
            }
            if let field = schemas.first,
               field.type != .vector || field.isArray {
                throw .unsupportedField(
                    index: indexName,
                    field: field,
                    reason: "Vector indexes require one canonical Vector"
                )
            }

        case .text(_, let mode):
            try requireMinimumCount(1)
            for field in schemas where field.type != .string {
                throw .unsupportedField(
                    index: indexName,
                    field: field,
                    reason: "Text indexes require String or [String]"
                )
            }
            switch mode {
            case .fullText(_, _, let ngramSize, let minimumTermLength):
                guard ngramSize > 0, minimumTermLength > 0 else {
                    throw .invalidConfiguration(
                        index: indexName,
                        reason: "Full-text n-gram size and minimum term length must be positive"
                    )
                }
            case .autocomplete(let minimum, let maximum):
                guard minimum > 0, maximum >= minimum else {
                    throw .invalidConfiguration(
                        index: indexName,
                        reason: "Autocomplete prefix bounds are invalid"
                    )
                }
            }

        case .spatial(_, let encoding, let level):
            try requireCount(1)
            let maximumLevel = encoding == .morton ? 20 : 30
            guard (0...maximumLevel).contains(level) else {
                throw .invalidConfiguration(
                    index: indexName,
                    reason: "Spatial level must be in 0...\(maximumLevel)"
                )
            }
            if let field = schemas.first,
               field.isArray || (field.type != .geographicPoint
                    && field.type != .geographicPosition) {
                throw .unsupportedField(
                    index: indexName,
                    field: field,
                    reason: "Spatial indexes require a geographic point or position"
                )
            }

        case .rank:
            try requireCount(1)
            if let score = schemas.first {
                try requireNumeric(
                    score,
                    reason: "Rank score must be numeric"
                )
            }

        case .graph(let definition, let includedFields):
            switch definition {
            case .property(_, let label, _, _, _):
                let minimumCount = label.isField ? 3 : 2
                guard schemas.count == minimumCount
                        || schemas.count == minimumCount + 1 else {
                    throw .invalidFieldCount(
                        index: indexName,
                        expected: minimumCount,
                        actual: schemas.count
                    )
                }
                for field in schemas where field.type != .string || field.isArray {
                    throw .unsupportedField(
                        index: indexName,
                        field: field,
                        reason: "Property-graph identity fields must be String"
                    )
                }
            case .rdf:
                guard schemas.count == 3 || schemas.count == 4 else {
                    throw .invalidFieldCount(
                        index: indexName,
                        expected: 4,
                        actual: schemas.count
                    )
                }
                for field in schemas where field.type != .rdfTerm || field.isArray {
                    throw .unsupportedField(
                        index: indexName,
                        field: field,
                        reason: "RDF dataset fields must be RDFTerm"
                    )
                }
            case .ontologyProjection(let individualIRIBase, _):
                guard schemas.isEmpty,
                      includedFields.isEmpty,
                      !individualIRIBase.isEmpty else {
                    throw .invalidConfiguration(
                        index: indexName,
                        reason: "Ontology projection requires an IRI base and no fields"
                    )
                }
            }

        case .custom(let definition):
            guard !definition.identifier.isEmpty else {
                throw .invalidConfiguration(
                    index: indexName,
                    reason: "Custom index identifier must not be empty"
                )
            }
            try requireMinimumCount(1)
        }
    }
}

private extension PropertyGraphLabel {
    var isField: Bool {
        if case .field = self { return true }
        return false
    }
}
