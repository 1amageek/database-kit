import DatabaseTypes



/// Schema - Type-independent schema management
///
/// **Design**: Type-independent database schema definition
/// - Uses Entity (metadata) with field names and IndexDescriptor
/// - Uses IndexDescriptor (metadata) instead of Index (runtime)
/// - Supports all upper layers (entity-layer, graph-layer, document-layer)
///
/// **Example usage**:
/// ```swift
/// let schema = try Schema(
///     [User.self, Order.self, Message.self],
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
    /// Represents the complete schema definition for a Persistable type.
    /// Designed after SwiftData's `Schema.Entity` — Entity IS the metadata.
    ///
    /// **Usage**:
    /// - Runtime: `Entity(from: User.self)` — full metadata + runtime type
    public struct Entity: Sendable, Equatable, Hashable {

        /// Entity name (same as Persistable.persistableType)
        public let name: String

        /// Field metadata (name, type, field number, optionality, array)
        public let fields: [FieldSchema]

        /// Directory path components (static paths and dynamic field references)
        public let directoryComponents: [DirectoryPathComponent]

        /// Directory resolution strategy compiled from `#Directory`.
        public let directoryLayer: DirectoryLayer

        /// Index definitions (type-erased)
        public let indexes: [IndexDescriptorMetadata]

        /// Enum metadata: fieldName → case names
        public let enumMetadata: [String: [String]]

        /// OWL class IRI (from @OWLClass macro, nil if not an ontology entity)
        public let ontologyClassIRI: String?

        /// OWL ObjectProperty IRI (from @OWLObjectProperty macro, nil if not an ObjectProperty entity)
        public let objectPropertyIRI: String?

        /// ObjectProperty source field name (from @OWLObjectProperty `from:`)
        public let objectPropertyFromField: String?

        /// ObjectProperty target field name (from @OWLObjectProperty `to:`)
        public let objectPropertyToField: String?

        /// OWL DataProperty IRIs (from @OWLDataProperty macros on fields)
        /// Persisted so that wire-format Schema.Entity can be validated
        /// even when persistableType is nil.
        public let dataPropertyIRIs: [String]?

        // MARK: - Runtime-Only Properties

        /// The Persistable type (for runtime type recovery)
        ///
        /// Used by database-framework to:
        /// - Create typed IndexMaintainers during migrations
        /// - Access directory path components at runtime
        /// - Check Polymorphable conformance
        ///
        /// nil when the entity describes a type unavailable in this process.
        public let persistableType: (any Persistable.Type)?

        /// Validated index descriptors available to the runtime.
        ///
        /// Empty when no compiled descriptor is available.
        public let indexDescriptors: [IndexDescriptor]

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

        // MARK: - Init: from Persistable type (runtime)

        /// Initialize from Persistable type
        public init(from type: any Persistable.Type) throws(SchemaEntityError) {
            let objPropInfo = Self.extractObjectPropertyInfo(from: type)
            let indexDescriptors: [IndexDescriptor]
            do {
                indexDescriptors = try type.indexDescriptors
            } catch let declarationError {
                throw .invalidIndexDeclaration(declarationError)
            }
            try self.init(
                name: type.persistableType,
                fields: type.fieldSchemas,
                directoryComponents: Self.extractDirectoryComponents(from: type),
                directoryLayer: type.directoryLayer,
                indexes: indexDescriptors.map { IndexDescriptorMetadata($0) },
                enumMetadata: Self.extractEnumMetadata(from: type),
                ontologyClassIRI: Self.extractOntologyClassIRI(from: type),
                objectPropertyIRI: objPropInfo?.iri,
                objectPropertyFromField: objPropInfo?.fromField,
                objectPropertyToField: objPropInfo?.toField,
                dataPropertyIRIs: Self.extractDataPropertyIRIs(from: type),
                persistableType: type,
                indexDescriptors: indexDescriptors
            )
        }

        // MARK: - Init: manual / decoded from wire

        /// Manual initializer (for testing, CLI, or decoded from wire)
        public init(
            name: String,
            fields: [FieldSchema],
            directoryComponents: [DirectoryPathComponent] = [],
            directoryLayer: DirectoryLayer = .default,
            indexes: [IndexDescriptorMetadata] = [],
            enumMetadata: [String: [String]] = [:],
            ontologyClassIRI: String? = nil,
            objectPropertyIRI: String? = nil,
            objectPropertyFromField: String? = nil,
            objectPropertyToField: String? = nil,
            dataPropertyIRIs: [String]? = nil
        ) throws(SchemaEntityError) {
            try self.init(
                name: name,
                fields: fields,
                directoryComponents: directoryComponents,
                directoryLayer: directoryLayer,
                indexes: indexes,
                enumMetadata: enumMetadata,
                ontologyClassIRI: ontologyClassIRI,
                objectPropertyIRI: objectPropertyIRI,
                objectPropertyFromField: objectPropertyFromField,
                objectPropertyToField: objectPropertyToField,
                dataPropertyIRIs: dataPropertyIRIs,
                persistableType: nil,
                indexDescriptors: []
            )
        }

        private init(
            name: String,
            fields: [FieldSchema],
            directoryComponents: [DirectoryPathComponent],
            directoryLayer: DirectoryLayer,
            indexes: [IndexDescriptorMetadata],
            enumMetadata: [String: [String]],
            ontologyClassIRI: String?,
            objectPropertyIRI: String?,
            objectPropertyFromField: String?,
            objectPropertyToField: String?,
            dataPropertyIRIs: [String]?,
            persistableType: (any Persistable.Type)?,
            indexDescriptors: [IndexDescriptor]
        ) throws(SchemaEntityError) {
            let fieldMaps = try Self.validate(
                name: name,
                fields: fields,
                directoryComponents: directoryComponents,
                directoryLayer: directoryLayer,
                indexes: indexes,
                enumMetadata: enumMetadata,
                ontologyClassIRI: ontologyClassIRI,
                objectPropertyIRI: objectPropertyIRI,
                objectPropertyFromField: objectPropertyFromField,
                objectPropertyToField: objectPropertyToField,
                dataPropertyIRIs: dataPropertyIRIs
            )
            self.name = name
            self.fields = fields
            self.directoryComponents = directoryComponents
            self.directoryLayer = directoryLayer
            self.indexes = indexes
            self.enumMetadata = enumMetadata
            self.ontologyClassIRI = ontologyClassIRI
            self.objectPropertyIRI = objectPropertyIRI
            self.objectPropertyFromField = objectPropertyFromField
            self.objectPropertyToField = objectPropertyToField
            self.dataPropertyIRIs = dataPropertyIRIs
            self.persistableType = persistableType
            self.indexDescriptors = indexDescriptors
            self.fieldsByName = fieldMaps.byName
            self.fieldsByNumber = fieldMaps.byNumber
        }

        // MARK: - Custom Equatable (compare semantic fields)

        public static func == (lhs: Entity, rhs: Entity) -> Bool {
            lhs.name == rhs.name &&
            lhs.fields == rhs.fields &&
            lhs.directoryComponents == rhs.directoryComponents &&
            lhs.directoryLayer == rhs.directoryLayer &&
            lhs.indexes == rhs.indexes &&
            lhs.enumMetadata == rhs.enumMetadata &&
            lhs.ontologyClassIRI == rhs.ontologyClassIRI &&
            lhs.objectPropertyIRI == rhs.objectPropertyIRI &&
            lhs.objectPropertyFromField == rhs.objectPropertyFromField &&
            lhs.objectPropertyToField == rhs.objectPropertyToField &&
            lhs.dataPropertyIRIs == rhs.dataPropertyIRIs
        }

        // MARK: - Custom Hashable (hash semantic fields)

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(fields)
            hasher.combine(directoryComponents)
            hasher.combine(directoryLayer)
            hasher.combine(indexes)
            hasher.combine(enumMetadata)
            hasher.combine(ontologyClassIRI)
            hasher.combine(objectPropertyIRI)
            hasher.combine(objectPropertyFromField)
            hasher.combine(objectPropertyToField)
            hasher.combine(dataPropertyIRIs)
        }

        // MARK: - Private Helpers

        private static func extractDirectoryComponents(from type: any Persistable.Type) -> [DirectoryPathComponent] {
            type.directoryPathComponents
        }

        /// Extract ontology class IRI from a type if it conforms to OWLClassEntity-like protocol.
        /// Uses runtime protocol check to avoid Core → Graph dependency.
        private static func extractOntologyClassIRI(from type: any Persistable.Type) -> String? {
            // Check if the type has ontologyClassIRI static property
            // This is generated by @OWLClass macro and exposed via OWLClassEntity protocol
            if let ontologyType = type as? any _OWLClassIRIProvider.Type {
                return ontologyType.ontologyClassIRI
            }
            return nil
        }

        /// Extract ObjectProperty info from a type if it conforms to OWLObjectPropertyEntity-like protocol.
        private static func extractObjectPropertyInfo(from type: any Persistable.Type) -> (iri: String, fromField: String, toField: String)? {
            if let objPropType = type as? any _OWLObjectPropertyIRIProvider.Type {
                return (objPropType.objectPropertyIRI, objPropType.fromFieldName, objPropType.toFieldName)
            }
            return nil
        }

        /// Extract data property IRIs from a type if it conforms to _DataPropertyIRIsProvider.
        private static func extractDataPropertyIRIs(from type: any Persistable.Type) -> [String]? {
            if let provider = type as? any _DataPropertyIRIsProvider.Type {
                let iris = provider.dataPropertyIRIs
                return iris.isEmpty ? nil : iris
            }
            return nil
        }

        private static func extractEnumMetadata(from type: any Persistable.Type) -> [String: [String]] {
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
            enumMetadata: [String: [String]],
            ontologyClassIRI: String?,
            objectPropertyIRI: String?,
            objectPropertyFromField: String?,
            objectPropertyToField: String?,
            dataPropertyIRIs: [String]?
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
                if let target = field.referenceTargetEntity {
                    guard field.type == .reference else {
                        throw .referenceTargetOnNonReferenceField(fieldName: field.name)
                    }
                    guard !target.isEmpty else {
                        throw .invalidReferenceTarget(fieldName: field.name)
                    }
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

            if let ontologyClassIRI, ontologyClassIRI.isEmpty {
                throw .emptyOntologyIRI
            }
            try validateObjectProperty(
                iri: objectPropertyIRI,
                fromField: objectPropertyFromField,
                toField: objectPropertyToField,
                fieldsByName: fieldsByName
            )

            var seenDataPropertyIRIs = Set<String>()
            for iri in dataPropertyIRIs ?? [] {
                guard !iri.isEmpty else {
                    throw .emptyDataPropertyIRI
                }
                guard seenDataPropertyIRIs.insert(iri).inserted else {
                    throw .duplicateDataPropertyIRI(iri)
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
            iri: String?,
            fromField: String?,
            toField: String?,
            fieldsByName: [String: FieldSchema]
        ) throws(SchemaEntityError) {
            switch (iri, fromField, toField) {
            case (nil, nil, nil):
                return
            case (.some(let iri), .some(let fromField), .some(let toField)):
                guard !iri.isEmpty else {
                    throw .emptyOntologyIRI
                }
                guard fieldsByName[fromField] != nil else {
                    throw .unknownObjectPropertyField(fromField)
                }
                guard fieldsByName[toField] != nil else {
                    throw .unknownObjectPropertyField(toField)
                }
            default:
                throw .incompleteObjectProperty
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

    /// Index descriptors (metadata only)
    public let indexDescriptors: [IndexDescriptor]

    /// Indexes by name for quick lookup
    internal let indexDescriptorsByName: [String: IndexDescriptor]

    /// Names of all concrete and polymorphic indexes in this schema.
    public var allIndexNames: Set<String> {
        Set(indexDescriptors.map { $0.name })
            .union(polymorphicGroups.flatMap { group in group.indexes.map { $0.name } })
    }

    // MARK: - Initialization

    /// Create schema from array of Persistable types
    ///
    /// - Parameters:
    ///   - types: Array of Persistable types
    ///   - version: Schema version
    ///   - indexDescriptors: Additional index descriptors (optional, merged with type-defined indexes)
    ///
    /// **Index Collection**:
    /// This initializer automatically collects IndexDescriptors from types:
    /// 1. Collects `indexDescriptors` from each Persistable type (defined by macros)
    /// 2. Merges with manually provided indexDescriptors
    ///
    /// **Example usage**:
    /// ```swift
    /// let schema = try Schema([User.self, Order.self])  // Indexes auto-collected
    /// ```
    public init(
        _ types: [any Persistable.Type],
        version: Version = Version(1, 0, 0),
        indexDescriptors: [IndexDescriptor] = []
    ) throws(SchemaError) {
        self.version = version
        self.encodingVersion = version

        // Build entities
        var entities: [Entity] = []
        var entitiesByName: [String: Entity] = [:]
        var polymorphicMembers: [String: [any Persistable.Type]] = [:]

        for type in types {
            let entity: Entity
            do {
                entity = try Entity(from: type)
            } catch {
                throw .invalidEntity(error)
            }
            guard entitiesByName[entity.name] == nil else {
                throw .duplicateEntityName(entity.name)
            }
            entities.append(entity)
            entitiesByName[entity.name] = entity
            if let polymorphicType = type as? any Polymorphable.Type {
                polymorphicMembers[polymorphicType.polymorphableType, default: []].append(type)
            }
        }

        self.entities = entities
        self.entitiesByName = entitiesByName

        let runtimePolymorphicMetadata = try Self.buildPolymorphicRuntimeMetadata(from: polymorphicMembers)
        self.polymorphicGroups = runtimePolymorphicMetadata.groups
        self.polymorphicGroupsByIdentifier = Dictionary(
            uniqueKeysWithValues: runtimePolymorphicMetadata.groups.map { ($0.identifier, $0) }
        )
        self.polymorphicIndexDescriptorsByIdentifierAndMemberName = runtimePolymorphicMetadata.descriptorsByIdentifierAndMemberName

        // Entity construction has already materialized and validated every
        // type-defined descriptor exactly once.
        var allIndexDescriptors = entities.flatMap { $0.indexDescriptors }

        // Merge with manually provided descriptors
        allIndexDescriptors.append(contentsOf: indexDescriptors)

        // Store index descriptors with duplicate check
        self.indexDescriptors = allIndexDescriptors
        var indexDescriptorsByName: [String: IndexDescriptor] = [:]
        for descriptor in allIndexDescriptors {
            if let existing = indexDescriptorsByName[descriptor.name] {
                throw .duplicateIndexName(
                    indexName: descriptor.name,
                    existingFields: existing.fieldNames,
                    duplicateFields: descriptor.fieldNames
                )
            }
            indexDescriptorsByName[descriptor.name] = descriptor
        }
        try Self.validatePolymorphicIndexNames(
            runtimePolymorphicMetadata.groups,
            against: indexDescriptorsByName
        )
        self.indexDescriptorsByName = indexDescriptorsByName
    }

    /// Initializer for manual Schema construction
    ///
    /// - Parameters:
    ///   - entities: Array of Entity objects
    ///   - version: Schema version
    ///   - indexDescriptors: Index descriptors (optional)
    public init(
        entities: [Entity],
        version: Version = Version(1, 0, 0),
        indexDescriptors: [IndexDescriptor] = []
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

        self.entities = entities
        self.entitiesByName = entitiesByName
        self.polymorphicGroups = []
        self.polymorphicGroupsByIdentifier = [:]
        self.polymorphicIndexDescriptorsByIdentifierAndMemberName = [:]

        // Collect index descriptors from entities + manual descriptors
        var allIndexDescriptors: [IndexDescriptor] = []
        for entity in entities {
            allIndexDescriptors.append(contentsOf: entity.indexDescriptors)
        }
        allIndexDescriptors.append(contentsOf: indexDescriptors)

        // Store index descriptors with duplicate check
        self.indexDescriptors = allIndexDescriptors
        var indexDescriptorsByName: [String: IndexDescriptor] = [:]
        for descriptor in allIndexDescriptors {
            if let existing = indexDescriptorsByName[descriptor.name] {
                throw .duplicateIndexName(
                    indexName: descriptor.name,
                    existingFields: existing.fieldNames,
                    duplicateFields: descriptor.fieldNames
                )
            }
            indexDescriptorsByName[descriptor.name] = descriptor
        }
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
    public func polymorphicIndexDescriptors(
        identifier: String,
        memberType: any Persistable.Type
    ) -> [IndexDescriptor] {
        polymorphicIndexDescriptorsByIdentifierAndMemberName[identifier]?[memberType.persistableType] ?? []
    }

    /// Get typed index descriptors for a concrete member of a polymorphic group.
    public func polymorphicIndexDescriptors<Member: Persistable>(
        identifier: String,
        memberType: Member.Type
    ) -> [IndexDescriptor] {
        polymorphicIndexDescriptors(identifier: identifier, memberType: memberType as any Persistable.Type)
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

    private struct PolymorphicRuntimeMetadata: Sendable {
        let groups: [PolymorphicGroup]
        let descriptorsByIdentifierAndMemberName: [String: [String: [IndexDescriptor]]]
    }

    private static func buildPolymorphicRuntimeMetadata(
        from membersByIdentifier: [String: [any Persistable.Type]]
    ) throws(SchemaError) -> PolymorphicRuntimeMetadata {
        var groups: [PolymorphicGroup] = []
        var descriptorsByIdentifierAndMemberName: [String: [String: [IndexDescriptor]]] = [:]

        for (identifier, memberTypes) in membersByIdentifier.sorted(by: { $0.key < $1.key }) {
            let sortedMemberTypes = memberTypes.sorted { $0.persistableType < $1.persistableType }
            let polymorphicTypes = sortedMemberTypes.compactMap { memberType -> (any Persistable.Type, any Polymorphable.Type)? in
                guard let polymorphicType = memberType as? any Polymorphable.Type else {
                    return nil
                }
                return (memberType, polymorphicType)
            }

            guard let first = polymorphicTypes.first else {
                continue
            }

            let directoryComponents = PolymorphicGroup.extractDirectoryComponents(
                from: first.1.polymorphicDirectoryPathComponents
            )
            let directoryLayer = first.1.polymorphicDirectoryLayer

            for (_, polymorphicType) in polymorphicTypes.dropFirst() {
                let components = PolymorphicGroup.extractDirectoryComponents(
                    from: polymorphicType.polymorphicDirectoryPathComponents
                )
                guard components == directoryComponents else {
                    throw .inconsistentPolymorphicDirectory(group: identifier)
                }
                guard polymorphicType.polymorphicDirectoryLayer == directoryLayer else {
                    throw .inconsistentPolymorphicDirectoryLayer(group: identifier)
                }
            }

            let memberTypeNames = polymorphicTypes.map { $0.0.persistableType }.sorted()
            let allMemberNames = Set(memberTypeNames)
            var descriptorsByMemberName: [String: [IndexDescriptor]] = [:]
            var logicalIndexByName: [String: PolymorphicIndexMetadata] = [:]
            var logicalIndexOrder: [String] = []
            var membersByIndexName: [String: Set<String>] = [:]

            for (memberType, polymorphicType) in polymorphicTypes {
                var descriptors: [IndexDescriptor] = []
                descriptors.reserveCapacity(polymorphicType.polymorphicIndexes.count)
                let definitions = polymorphicType.polymorphicIndexes
                for definition in definitions {
                    do {
                        descriptors.append(
                            try definition.descriptor(
                                fieldSchemas: memberType.fieldSchemas
                            )
                        )
                    } catch let declarationError {
                        throw .invalidIndexDeclaration(declarationError)
                    }
                }
                descriptorsByMemberName[memberType.persistableType] = descriptors

                var seenNamesForMember: Set<String> = []
                for (definition, descriptor) in zip(definitions, descriptors) {
                    guard seenNamesForMember.insert(descriptor.name).inserted else {
                        throw .duplicatePolymorphicIndex(
                            group: identifier,
                            member: memberType.persistableType,
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

                    membersByIndexName[descriptor.name, default: []].insert(memberType.persistableType)
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

        return PolymorphicRuntimeMetadata(
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
        // Compare versions
        guard lhs.version == rhs.version else {
            return false
        }

        // Compare entity names (Entity is not Equatable due to IndexDescriptor)
        let lhsNames = Set(lhs.entitiesByName.keys)
        let rhsNames = Set(rhs.entitiesByName.keys)
        let lhsGroupNames = Set(lhs.polymorphicGroupsByIdentifier.keys)
        let rhsGroupNames = Set(rhs.polymorphicGroupsByIdentifier.keys)
        return lhsNames == rhsNames && lhsGroupNames == rhsGroupNames
    }
}

// MARK: - Hashable

extension Schema: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(version)
        // Use sorted entity names to ensure order-independent hashing
        for name in entitiesByName.keys.sorted() {
            hasher.combine(name)
        }
        for identifier in polymorphicGroupsByIdentifier.keys.sorted() {
            hasher.combine(identifier)
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
