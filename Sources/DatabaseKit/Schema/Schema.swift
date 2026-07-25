import DatabaseTypes



/// Schema - Type-independent schema management
///
/// **Design**: Type-independent database schema definition
/// - Uses immutable Entity values with field, index, relationship, and graph metadata
/// - Does not retain application metatypes or runtime execution capabilities
/// - Supports all upper layers (entity-layer, graph-layer, document-layer)
///
/// **Example usage**:
/// ```swift
/// let schema = try Schema(
///     entities: [
///         try User.schemaEntity,
///         try Order.schemaEntity,
///         try Message.schemaEntity
///     ],
///     version: Schema.Version(1, 0, 0)
/// )
///
/// // Entity access
/// let userEntity = schema.entity(for: User.self)
/// print("Indices: \(userEntity?.indexDescriptors ?? [])")
/// ```
public final class Schema: Sendable {

    // MARK: - Version

    /// Schema version
    ///
    /// Uses semantic versioning:
    /// - major: Incompatible changes
    /// - minor: Backward-compatible feature additions
    /// - patch: Backward-compatible bug fixes
    public typealias Version = SchemaVersion

    // MARK: - Entity

    /// Entity metadata (type-independent)
    ///
    /// Represents the complete schema definition for a persisted model.
    public struct Entity: Sendable, Equatable, Hashable {

        /// Entity name (same as Persistable.persistableType)
        public let name: String

        /// Canonical identifier shape used by storage and DatabaseWire.
        public let identifierType: PersistableIdentifierType

        /// Field metadata (name, type, field number, optionality, array)
        public let fields: [FieldSchema]

        /// Directory path components (static paths and dynamic field references)
        public let directoryComponents: [DirectoryPathComponent]

        /// Directory resolution strategy compiled from `#Directory`.
        public let directoryLayer: DirectoryLayer

        /// Canonical index declarations.
        public let indexes: [IndexDescriptorMetadata]

        /// Typed relationship declarations owned by this entity.
        public let relationships: [RelationshipDescriptor]

        /// Static field-level authorization declarations.
        public let fieldAccessRules: [FieldAccessRule]

        /// Enum metadata: fieldName → case names
        public let enumMetadata: [String: [String]]

        /// Optional OWL binding compiled from model annotations.
        public let ontology: OntologyBinding?

        /// Optional membership in a protocol-oriented polymorphic group.
        public let polymorphicMembership: PolymorphicMembership?

        private let fieldsByName: [String: FieldSchema]
        private let fieldsByNumber: [Int: FieldSchema]

        // MARK: - Computed Properties

        /// All field names
        public var allFields: [String] {
            fields.map { $0.name }
        }

        /// Build field name → FieldSchema map (for encoding)
        public var fieldMapByName: [String: FieldSchema] {
            fieldsByName
        }

        /// Build field number → FieldSchema map (for decoding)
        public var fieldMapByNumber: [Int: FieldSchema] {
            fieldsByNumber
        }

        /// Validated concrete index declarations reconstructed from canonical metadata.
        public var indexDescriptors: [IndexDescriptor] {
            indexes.map(IndexDescriptor.init(validatedMetadata:))
        }

        /// Whether this type has dynamic directory components requiring partition values
        public var hasDynamicDirectory: Bool {
            directoryComponents.contains {
                if case .dynamicField = $0 { return true }
                return false
            }
        }

        /// Field names of dynamic directory components
        public var dynamicFieldNames: [String] {
            directoryComponents.compactMap {
                if case .dynamicField(let name) = $0 { return name }
                return nil
            }
        }

        // MARK: - Directory Resolution

        /// Resolve directoryComponents to a concrete [String] path
        ///
        /// - Parameter partitionValues: Mapping of field names to partition values
        /// - Throws: DirectoryPathError.missingFields if a dynamic field has no value
        /// - Returns: Resolved directory path as string array
        public func resolvedDirectoryPath(partitionValues: [String: String] = [:]) throws -> [String] {
            try directoryComponents.map { component in
                switch component {
                case .staticPath(let value):
                    return value
                case .dynamicField(let fieldName):
                    guard let value = partitionValues[fieldName] else {
                        throw DirectoryPathError.missingFields([fieldName])
                    }
                    return value
                }
            }
        }

        // MARK: - Init: from a statically known model

        /// Compile a model declaration into a pure schema value.
        public init<Model: Persistable>(
            from type: Model.Type,
            including additionalIndexes: [IndexDescriptor] = []
        ) throws(SchemaEntityError) {
            var indexDescriptors: [IndexDescriptor]
            do {
                indexDescriptors = try type.indexDescriptors
            } catch let declarationError {
                throw .invalidIndexDeclaration(declarationError)
            }
            indexDescriptors.append(contentsOf: additionalIndexes)
            try self.init(
                name: type.persistableType,
                identifierType: type.persistableIdentifierType,
                fields: type.fieldSchemas,
                directoryComponents: type.directoryPathComponents,
                directoryLayer: type.directoryLayer,
                indexes: indexDescriptors.map { IndexDescriptorMetadata($0) },
                relationships: type.relationshipDescriptors,
                fieldAccessRules: type.fieldAccessRules,
                enumMetadata: Self.extractEnumMetadata(from: type),
                ontology: type.ontologyBinding,
                polymorphicMembership: type.polymorphicMembership
            )
        }

        // MARK: - Init: manual / decoded from wire

        /// Manual initializer (for testing, CLI, or decoded from wire)
        public init(
            name: String,
            identifierType: PersistableIdentifierType,
            fields: [FieldSchema],
            directoryComponents: [DirectoryPathComponent] = [],
            directoryLayer: DirectoryLayer = .default,
            indexes: [IndexDescriptorMetadata] = [],
            relationships: [RelationshipDescriptor] = [],
            fieldAccessRules: [FieldAccessRule] = [],
            enumMetadata: [String: [String]] = [:],
            ontology: OntologyBinding? = nil,
            polymorphicMembership: PolymorphicMembership? = nil
        ) throws(SchemaEntityError) {
            let fieldMaps = try Self.validate(
                name: name,
                fields: fields,
                directoryComponents: directoryComponents,
                directoryLayer: directoryLayer,
                indexes: indexes,
                relationships: relationships,
                fieldAccessRules: fieldAccessRules,
                enumMetadata: enumMetadata,
                ontology: ontology,
                polymorphicMembership: polymorphicMembership
            )
            self.name = name
            self.identifierType = identifierType
            self.fields = fields
            self.directoryComponents = directoryComponents
            self.directoryLayer = directoryLayer
            self.indexes = indexes
            self.relationships = relationships
            self.fieldAccessRules = fieldAccessRules
            self.enumMetadata = enumMetadata
            self.ontology = ontology
            self.polymorphicMembership = polymorphicMembership
            self.fieldsByName = fieldMaps.byName
            self.fieldsByNumber = fieldMaps.byNumber
        }

        // MARK: - Custom Equatable (compare semantic fields)

        public static func == (lhs: Entity, rhs: Entity) -> Bool {
            lhs.name == rhs.name &&
            lhs.identifierType == rhs.identifierType &&
            lhs.fields == rhs.fields &&
            lhs.directoryComponents == rhs.directoryComponents &&
            lhs.directoryLayer == rhs.directoryLayer &&
            lhs.indexes == rhs.indexes &&
            lhs.relationships == rhs.relationships &&
            lhs.fieldAccessRules == rhs.fieldAccessRules &&
            lhs.enumMetadata == rhs.enumMetadata &&
            lhs.ontology == rhs.ontology &&
            lhs.polymorphicMembership == rhs.polymorphicMembership
        }

        // MARK: - Custom Hashable (hash semantic fields)

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(identifierType)
            hasher.combine(fields)
            hasher.combine(directoryComponents)
            hasher.combine(directoryLayer)
            hasher.combine(indexes)
            hasher.combine(relationships)
            hasher.combine(fieldAccessRules)
            hasher.combine(enumMetadata)
            hasher.combine(ontology)
            hasher.combine(polymorphicMembership)
        }

        // MARK: - Private Helpers

        private static func extractEnumMetadata<Model: Persistable>(
            from type: Model.Type
        ) -> [String: [String]] {
            var result: [String: [String]] = [:]
            for field in type.allFields {
                if let meta = type.enumMetadata(for: field) {
                    result[field] = meta.cases
                }
            }
            return result
        }

        private static func validate(
            name: String,
            fields: [FieldSchema],
            directoryComponents: [DirectoryPathComponent],
            directoryLayer: DirectoryLayer,
            indexes: [IndexDescriptorMetadata],
            relationships: [RelationshipDescriptor],
            fieldAccessRules: [FieldAccessRule],
            enumMetadata: [String: [String]],
            ontology: OntologyBinding?,
            polymorphicMembership: PolymorphicMembership?
        ) throws(SchemaEntityError) -> (
            byName: [String: FieldSchema],
            byNumber: [Int: FieldSchema]
        ) {
            guard !name.isEmpty else {
                throw .emptyEntityName
            }
            var fieldsByName: [String: FieldSchema] = [:]
            var fieldsByNumber: [Int: FieldSchema] = [:]
            for field in fields {
                guard !field.name.isEmpty else {
                    throw .emptyFieldName(fieldNumber: field.fieldNumber)
                }
                guard field.fieldNumber > 0 else {
                    throw .invalidFieldNumber(
                        fieldName: field.name,
                        fieldNumber: field.fieldNumber
                    )
                }
                guard fieldsByName.updateValue(field, forKey: field.name) == nil else {
                    throw .duplicateFieldName(field.name)
                }
                if let existing = fieldsByNumber.updateValue(field, forKey: field.fieldNumber) {
                    throw .duplicateFieldNumber(
                        fieldNumber: field.fieldNumber,
                        fieldNames: [existing.name, field.name].sorted()
                    )
                }
                if field.type == .reference {
                    guard let target = field.referenceTargetEntity else {
                        throw .missingReferenceTarget(fieldName: field.name)
                    }
                    guard !target.isEmpty else {
                        throw .invalidReferenceTarget(fieldName: field.name)
                    }
                } else if field.referenceTargetEntity != nil {
                    throw .referenceTargetOnNonReferenceField(
                        fieldName: field.name
                    )
                }
            }

            var hasDynamicDirectoryField = false
            for (position, component) in directoryComponents.enumerated() {
                switch component {
                case .staticPath(let value):
                    guard !value.isEmpty else {
                        throw .emptyDirectoryPathComponent(position: position)
                    }
                case .dynamicField(let fieldName):
                    hasDynamicDirectoryField = true
                    guard fieldsByName[fieldName] != nil else {
                        throw .unknownDirectoryField(fieldName)
                    }
                }
            }
            if directoryLayer == .partition, !hasDynamicDirectoryField {
                throw .partitionDirectoryRequiresDynamicField
            }

            var indexNames = Set<String>()
            for index in indexes {
                guard !index.name.isEmpty else {
                    throw .emptyIndexName
                }
                guard indexNames.insert(index.name).inserted else {
                    throw .duplicateIndexName(index.name)
                }
                guard !index.kind.identifier.isEmpty else {
                    throw .emptyIndexKindIdentifier(indexName: index.name)
                }
                for fieldName in index.fieldNames {
                    try validateIndexField(
                        fieldName,
                        indexName: index.name,
                        fieldsByName: fieldsByName,
                        stored: false
                    )
                }
                for fieldName in index.storedFieldNames {
                    try validateIndexField(
                        fieldName,
                        indexName: index.name,
                        fieldsByName: fieldsByName,
                        stored: true
                    )
                }
            }

            var relationshipNames = Set<String>()
            for relationship in relationships {
                guard relationship.ownerTypeName == name else {
                    throw .invalidRelationshipOwner(
                        relationship: relationship.name,
                        expected: name,
                        actual: relationship.ownerTypeName
                    )
                }
                guard relationshipNames.insert(relationship.name).inserted else {
                    throw .duplicateRelationshipName(relationship.name)
                }
                guard !relationship.relatedTypeName.isEmpty else {
                    throw .emptyRelationshipTarget(relationship.name)
                }
                guard
                    let fieldNumber = Int(exactly: relationship.propertyFieldNumber),
                    let field = fieldsByNumber[fieldNumber],
                    field.name == relationship.propertyName
                else {
                    throw .invalidRelationshipField(
                        relationship: relationship.name,
                        fieldName: relationship.propertyName,
                        fieldNumber: relationship.propertyFieldNumber
                    )
                }
                guard field.type == .reference else {
                    throw .relationshipOnNonReferenceField(
                        relationship: relationship.name,
                        fieldName: field.name
                    )
                }
                guard
                    field.referenceTargetEntity
                        == relationship.relatedTypeName
                else {
                    throw .relationshipTargetMismatch(
                        relationship: relationship.name,
                        fieldTarget: field.referenceTargetEntity ?? "",
                        relationshipTarget: relationship.relatedTypeName
                    )
                }
            }

            var authorizedFieldNames = Set<String>()
            for rule in fieldAccessRules {
                guard
                    let field = fieldsByNumber[rule.field.number],
                    field.name == rule.field.name
                else {
                    throw .invalidFieldAccessRule(
                        fieldName: rule.field.name,
                        fieldNumber: rule.field.number
                    )
                }
                guard authorizedFieldNames.insert(rule.field.name).inserted else {
                    throw .duplicateFieldAccessRule(rule.field.name)
                }
            }

            for (fieldName, cases) in enumMetadata {
                guard let field = fieldsByName[fieldName] else {
                    throw .unknownEnumField(fieldName)
                }
                guard field.type == .enum else {
                    throw .enumMetadataOnNonEnumField(fieldName)
                }
                var caseNames = Set<String>()
                for caseName in cases {
                    guard !caseName.isEmpty else {
                        throw .emptyEnumCase(fieldName: fieldName)
                    }
                    guard caseNames.insert(caseName).inserted else {
                        throw .duplicateEnumCase(fieldName: fieldName, caseName: caseName)
                    }
                }
            }

            var seenDataPropertyIRIs = Set<String>()
            for iri in ontology?.dataPropertyIRIs ?? [] {
                guard !iri.isEmpty else {
                    throw .emptyDataPropertyIRI
                }
                guard seenDataPropertyIRIs.insert(iri).inserted else {
                    throw .duplicateDataPropertyIRI(iri)
                }
            }
            switch ontology {
            case nil:
                break
            case .owlClass(let iri, _):
                guard !iri.isEmpty else {
                    throw .emptyOntologyIRI
                }
            case .owlObjectProperty(let iri, let fromField, let toField, _):
                try validateObjectProperty(
                    iri: iri,
                    fromField: fromField,
                    toField: toField,
                    fieldsByName: fieldsByName
                )
            }

            if let polymorphicMembership {
                guard !polymorphicMembership.identifier.isEmpty else {
                    throw .emptyPolymorphicGroupIdentifier
                }
                for (position, component) in polymorphicMembership.directoryComponents.enumerated() {
                    guard case .staticPath(let value) = component, !value.isEmpty else {
                        throw .invalidPolymorphicDirectoryComponent(position: position)
                    }
                }
            }

            return (fieldsByName, fieldsByNumber)
        }

        private static func validateIndexField(
            _ fieldName: String,
            indexName: String,
            fieldsByName: [String: FieldSchema],
            stored: Bool
        ) throws(SchemaEntityError) {
            guard !fieldName.isEmpty else {
                throw .emptyIndexFieldName(indexName: indexName)
            }
            let rootFieldName = fieldName.split(
                separator: ".",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )[0]
            guard fieldsByName[String(rootFieldName)] != nil else {
                if stored {
                    throw .unknownStoredField(indexName: indexName, fieldName: fieldName)
                }
                throw .unknownIndexField(indexName: indexName, fieldName: fieldName)
            }
        }

        private static func validateObjectProperty(
            iri: String,
            fromField: String,
            toField: String,
            fieldsByName: [String: FieldSchema]
        ) throws(SchemaEntityError) {
            guard !iri.isEmpty else {
                throw .emptyOntologyIRI
            }
            guard fieldsByName[fromField] != nil else {
                throw .unknownObjectPropertyField(fromField)
            }
            guard fieldsByName[toField] != nil else {
                throw .unknownObjectPropertyField(toField)
            }
        }
    }

    // MARK: - Properties

    /// Schema version
    public let version: Version

    /// Encoding version (for compatibility)
    public let encodingVersion: Version

    /// All entities
    public let entities: [Entity]

    /// Access entities by name
    public let entitiesByName: [String: Entity]

    /// All polymorphic protocol groups
    public let polymorphicGroups: [PolymorphicGroup]

    /// Access polymorphic groups by identifier
    public let polymorphicGroupsByIdentifier: [String: PolymorphicGroup]

    /// Materialized index descriptors for each concrete polymorphic member.
    private let polymorphicIndexDescriptorsByIdentifierAndMemberName: [String: [String: [IndexDescriptor]]]

    /// All concrete entity index descriptors in declaration order.
    public var indexDescriptors: [IndexDescriptor] {
        entities.flatMap { $0.indexDescriptors }
    }

    /// Indexes by name for quick lookup
    internal let indexDescriptorsByName: [String: IndexDescriptor]

    /// Names of all concrete and polymorphic indexes in this schema.
    public var allIndexNames: Set<String> {
        Set(indexDescriptors.map { $0.name })
            .union(polymorphicGroups.flatMap { group in group.indexes.map { $0.name } })
    }

    // MARK: - Initialization

    /// Construct a schema from pure, statically compiled entity declarations.
    ///
    /// - Parameters:
    ///   - entities: Array of Entity objects
    ///   - version: Schema version
    public init(
        entities: [Entity],
        version: Version = Version(1, 0, 0)
    ) throws(SchemaError) {
        self.version = version
        self.encodingVersion = version

        // Build entity maps
        var entitiesByName: [String: Entity] = [:]
        for entity in entities {
            guard entitiesByName[entity.name] == nil else {
                throw .duplicateEntityName(entity.name)
            }
            entitiesByName[entity.name] = entity
        }
        try Self.validateEntityReferences(
            entities: entities,
            entitiesByName: entitiesByName
        )

        self.entities = entities
        self.entitiesByName = entitiesByName

        let polymorphicMetadata = try Self.buildPolymorphicMetadata(
            from: entities
        )
        self.polymorphicGroups = polymorphicMetadata.groups
        self.polymorphicGroupsByIdentifier = Dictionary(
            uniqueKeysWithValues: polymorphicMetadata.groups.map {
                ($0.identifier, $0)
            }
        )
        self.polymorphicIndexDescriptorsByIdentifierAndMemberName =
            polymorphicMetadata.descriptorsByIdentifierAndMemberName

        // Store index descriptors with duplicate check
        var indexDescriptorsByName: [String: IndexDescriptor] = [:]
        for entity in entities {
            for descriptor in entity.indexDescriptors {
                if let existing = indexDescriptorsByName[descriptor.name] {
                    throw .duplicateIndexName(
                        indexName: descriptor.name,
                        existingFields: existing.fieldNames,
                        duplicateFields: descriptor.fieldNames
                    )
                }
                indexDescriptorsByName[descriptor.name] = descriptor
            }
        }
        try Self.validatePolymorphicIndexNames(
            polymorphicMetadata.groups,
            against: indexDescriptorsByName
        )
        self.indexDescriptorsByName = indexDescriptorsByName
    }

    // MARK: - Entity Access

    /// Get entity for type
    ///
    /// - Parameter type: Persistable type
    /// - Returns: Entity (nil if not found)
    public func entity<T: Persistable>(for type: T.Type) -> Entity? {
        return entitiesByName[T.persistableType]
    }

    /// Get entity by name
    ///
    /// - Parameter name: Entity name
    /// - Returns: Entity (nil if not found)
    public func entity(named name: String) -> Entity? {
        return entitiesByName[name]
    }

    /// Get polymorphic group by identifier.
    ///
    /// - Parameter identifier: Polymorphic protocol identifier
    /// - Returns: Group metadata (nil if not found)
    public func polymorphicGroup(identifier: String) -> PolymorphicGroup? {
        polymorphicGroupsByIdentifier[identifier]
    }

    /// Get logical index metadata for a polymorphic group.
    ///
    /// Logical polymorphic metadata is validated across all concrete members at
    /// schema construction time.
    public func polymorphicIndexCatalog(identifier: String) -> [PolymorphicIndexMetadata] {
        polymorphicGroupsByIdentifier[identifier]?.indexes ?? []
    }

    /// Find the polymorphic group that owns a logical index name.
    public func polymorphicGroup(containingIndexNamed indexName: String) -> PolymorphicGroup? {
        polymorphicGroups.first { group in
            group.indexes.contains { $0.name == indexName }
        }
    }

    /// Get typed index descriptors for a concrete member of a polymorphic group.
    ///
    /// Polymorphic indexes share one logical index name, while field numbers are
    /// concrete-schema-specific. Runtime write maintenance uses this accessor so
    /// each member receives its resolved field identities.
    public func polymorphicIndexDescriptors<Member: Persistable>(
        identifier: String,
        memberType: Member.Type
    ) -> [IndexDescriptor] {
        polymorphicIndexDescriptorsByIdentifierAndMemberName[
            identifier
        ]?[Member.persistableType] ?? []
    }

    // MARK: - Index Access

    /// Get index descriptor by name
    ///
    /// - Parameter name: Index name
    /// - Returns: IndexDescriptor (nil if not found)
    public func indexDescriptor(named name: String) -> IndexDescriptor? {
        return indexDescriptorsByName[name]
    }

    /// Get index descriptors for a specific item type
    ///
    /// Returns all index descriptors from the entity's indexDescriptors.
    ///
    /// - Parameter itemType: The item type name
    /// - Returns: Array of applicable index descriptors
    public func indexDescriptors(for itemType: String) -> [IndexDescriptor] {
        guard let entity = entitiesByName[itemType] else {
            return []
        }
        return entity.indexDescriptors
    }

    private struct CompiledPolymorphicMetadata: Sendable {
        let groups: [PolymorphicGroup]
        let descriptorsByIdentifierAndMemberName: [String: [String: [IndexDescriptor]]]
    }

    private static func buildPolymorphicMetadata(
        from entities: [Entity]
    ) throws(SchemaError) -> CompiledPolymorphicMetadata {
        var membersByIdentifier: [String: [Entity]] = [:]
        for entity in entities {
            guard let membership = entity.polymorphicMembership else {
                continue
            }
            membersByIdentifier[membership.identifier, default: []].append(
                entity
            )
        }
        var groups: [PolymorphicGroup] = []
        var descriptorsByIdentifierAndMemberName: [String: [String: [IndexDescriptor]]] = [:]

        for (identifier, members) in membersByIdentifier.sorted(
            by: { $0.key < $1.key }
        ) {
            let sortedMembers = members.sorted { $0.name < $1.name }
            guard
                let firstEntity = sortedMembers.first,
                let firstMembership = firstEntity.polymorphicMembership
            else {
                continue
            }

            let directoryComponents = firstMembership.directoryComponents
            let directoryLayer = firstMembership.directoryLayer

            for entity in sortedMembers.dropFirst() {
                guard let membership = entity.polymorphicMembership else {
                    continue
                }
                guard membership.directoryComponents == directoryComponents else {
                    throw .inconsistentPolymorphicDirectory(group: identifier)
                }
                guard membership.directoryLayer == directoryLayer else {
                    throw .inconsistentPolymorphicDirectoryLayer(group: identifier)
                }
            }

            let memberTypeNames = sortedMembers.map { $0.name }
            let allMemberNames = Set(memberTypeNames)
            var descriptorsByMemberName: [String: [IndexDescriptor]] = [:]
            var logicalIndexByName: [String: PolymorphicIndexMetadata] = [:]
            var logicalIndexOrder: [String] = []
            var membersByIndexName: [String: Set<String>] = [:]

            for entity in sortedMembers {
                guard let membership = entity.polymorphicMembership else {
                    continue
                }
                var descriptors: [IndexDescriptor] = []
                descriptors.reserveCapacity(membership.indexes.count)
                let definitions = membership.indexes
                for definition in definitions {
                    do {
                        descriptors.append(
                            try definition.descriptor(
                                fieldSchemas: entity.fields
                            )
                        )
                    } catch let declarationError {
                        throw .invalidIndexDeclaration(declarationError)
                    }
                }
                descriptorsByMemberName[entity.name] = descriptors

                var seenNamesForMember: Set<String> = []
                for (definition, descriptor) in zip(definitions, descriptors) {
                    guard seenNamesForMember.insert(descriptor.name).inserted else {
                        throw .duplicatePolymorphicIndex(
                            group: identifier,
                            member: entity.name,
                            indexName: descriptor.name
                        )
                    }

                    let logicalDescriptor = PolymorphicIndexMetadata(
                        descriptor: descriptor,
                        fields: definition.fields
                    )
                    if let existing = logicalIndexByName[descriptor.name] {
                        guard existing == logicalDescriptor else {
                            throw .inconsistentPolymorphicIndex(
                                group: identifier,
                                indexName: descriptor.name
                            )
                        }
                    } else {
                        logicalIndexByName[descriptor.name] = logicalDescriptor
                        logicalIndexOrder.append(descriptor.name)
                    }

                    membersByIndexName[
                        descriptor.name,
                        default: []
                    ].insert(entity.name)
                }
            }

            for (indexName, declaringMembers) in membersByIndexName {
                guard declaringMembers == allMemberNames else {
                    throw .incompletePolymorphicIndex(
                        group: identifier,
                        indexName: indexName,
                        declaringMembers: declaringMembers.sorted(),
                        expectedMembers: memberTypeNames
                    )
                }
            }

            descriptorsByIdentifierAndMemberName[identifier] = descriptorsByMemberName
            groups.append(
                PolymorphicGroup(
                    identifier: identifier,
                    directoryComponents: directoryComponents,
                    directoryLayer: directoryLayer,
                    indexes: logicalIndexOrder.compactMap { logicalIndexByName[$0] },
                    memberTypeNames: memberTypeNames
                )
            )
        }

        return CompiledPolymorphicMetadata(
            groups: groups.sorted { $0.identifier < $1.identifier },
            descriptorsByIdentifierAndMemberName: descriptorsByIdentifierAndMemberName
        )
    }

    private static func validatePolymorphicIndexNames(
        _ groups: [PolymorphicGroup],
        against indexDescriptorsByName: [String: IndexDescriptor]
    ) throws(SchemaError) {
        var groupByIndexName: [String: String] = [:]
        for group in groups {
            for index in group.indexes {
                if let existing = indexDescriptorsByName[index.name] {
                    throw .duplicateIndexName(
                        indexName: index.name,
                        existingFields: existing.fieldNames,
                        duplicateFields: ["polymorphic:\(group.identifier)"]
                    )
                }
                if let existingGroup = groupByIndexName[index.name] {
                    throw .duplicatePolymorphicIndexAcrossGroups(
                        indexName: index.name,
                        firstGroup: existingGroup,
                        secondGroup: group.identifier
                    )
                }
                groupByIndexName[index.name] = group.identifier
            }
        }
    }

    private static func validateEntityReferences(
        entities: [Entity],
        entitiesByName: [String: Entity]
    ) throws(SchemaError) {
        for entity in entities {
            for field in entity.fields {
                guard let target = field.referenceTargetEntity else {
                    continue
                }
                guard entitiesByName[target] != nil else {
                    throw .unknownReferenceTarget(
                        entity: entity.name,
                        field: field.name,
                        target: target
                    )
                }
            }
        }
    }

}

// MARK: - CustomDebugStringConvertible

extension Schema: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "Schema(version: \(version), entities: \(entities.count))"
    }
}

// MARK: - Equatable

extension Schema: Equatable {
    public static func == (lhs: Schema, rhs: Schema) -> Bool {
        lhs.version == rhs.version
            && lhs.encodingVersion == rhs.encodingVersion
            && lhs.entitiesByName == rhs.entitiesByName
            && lhs.polymorphicGroupsByIdentifier
                == rhs.polymorphicGroupsByIdentifier
            && lhs.indexDescriptorsByName == rhs.indexDescriptorsByName
    }
}

// MARK: - Hashable

extension Schema: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(version)
        hasher.combine(encodingVersion)
        for name in entitiesByName.keys.sorted() {
            hasher.combine(name)
            hasher.combine(entitiesByName[name])
        }
        for identifier in polymorphicGroupsByIdentifier.keys.sorted() {
            hasher.combine(identifier)
            hasher.combine(polymorphicGroupsByIdentifier[identifier])
        }
        for name in indexDescriptorsByName.keys.sorted() {
            hasher.combine(name)
            hasher.combine(indexDescriptorsByName[name])
        }
    }
}

// MARK: - SchemaError

/// Errors that can occur during Schema validation
public enum SchemaError: Error, CustomStringConvertible, Sendable, Equatable {
    /// An entity declaration violates intrinsic schema catalog invariants.
    case invalidEntity(SchemaEntityError)

    /// Duplicate entity name detected.
    case duplicateEntityName(String)

    /// Duplicate index name detected across entities
    ///
    /// Index names must be unique across all entities in a schema.
    /// This error provides details about both the existing and duplicate index.
    case duplicateIndexName(indexName: String, existingFields: [String], duplicateFields: [String])

    /// An index declaration failed its concrete type or configuration contract.
    case invalidIndexDeclaration(IndexDeclarationError)

    /// A reference field targets an entity absent from the schema.
    case unknownReferenceTarget(
        entity: String,
        field: String,
        target: String
    )

    /// Concrete members disagree on the directory path of a polymorphic group.
    case inconsistentPolymorphicDirectory(group: String)

    /// Concrete members disagree on the directory layer of a polymorphic group.
    case inconsistentPolymorphicDirectoryLayer(group: String)

    /// A concrete member declares the same polymorphic index more than once.
    case duplicatePolymorphicIndex(group: String, member: String, indexName: String)

    /// Concrete members disagree on the logical metadata of a polymorphic index.
    case inconsistentPolymorphicIndex(group: String, indexName: String)

    /// A polymorphic index is not declared by every concrete member.
    case incompletePolymorphicIndex(
        group: String,
        indexName: String,
        declaringMembers: [String],
        expectedMembers: [String]
    )

    /// Two polymorphic groups declare the same global index name.
    case duplicatePolymorphicIndexAcrossGroups(
        indexName: String,
        firstGroup: String,
        secondGroup: String
    )

    public var description: String {
        switch self {
        case .invalidEntity(let error):
            return "Invalid entity schema: \(error.description)"
        case .duplicateEntityName(let name):
            return "Duplicate entity name '\(name)' detected. Entity names must be unique within a schema."
        case .duplicateIndexName(let indexName, let existingFields, let duplicateFields):
            let existingDesc = existingFields.joined(separator: ", ")
            let duplicateDesc = duplicateFields.joined(separator: ", ")
            return "Duplicate index name '\(indexName)' detected. " +
                   "Existing index fields: [\(existingDesc)], " +
                   "duplicate index fields: [\(duplicateDesc)]. " +
                   "Index names must be unique across all entities in the schema."
        case .invalidIndexDeclaration(let error):
            return error.description
        case .unknownReferenceTarget(let entity, let field, let target):
            return "Entity '\(entity)' field '\(field)' references missing entity '\(target)'."
        case .inconsistentPolymorphicDirectory(let group):
            return "Polymorphic group '\(group)' has inconsistent directory components across member types."
        case .inconsistentPolymorphicDirectoryLayer(let group):
            return "Polymorphic group '\(group)' has inconsistent directory layers across member types."
        case .duplicatePolymorphicIndex(let group, let member, let indexName):
            return "Polymorphic group '\(group)' member '\(member)' declares duplicate index '\(indexName)'."
        case .inconsistentPolymorphicIndex(let group, let indexName):
            return "Polymorphic group '\(group)' index '\(indexName)' has inconsistent logical metadata across member types."
        case .incompletePolymorphicIndex(
            let group,
            let indexName,
            let declaringMembers,
            let expectedMembers
        ):
            return "Polymorphic group '\(group)' index '\(indexName)' must be declared by every member type. " +
                "Declared by: \(declaringMembers.joined(separator: ", ")); " +
                "expected: \(expectedMembers.joined(separator: ", "))."
        case .duplicatePolymorphicIndexAcrossGroups(let indexName, let firstGroup, let secondGroup):
            return "Duplicate polymorphic index name '\(indexName)' detected in groups " +
                "'\(firstGroup)' and '\(secondGroup)'."
        }
    }
}
