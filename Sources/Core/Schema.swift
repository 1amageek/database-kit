
/// Schema - Type-independent schema management
///
/// **Design**: FDBRuntime's type-independent schema definition
/// - Uses Entity (metadata) with field names and IndexDescriptor
/// - Uses IndexDescriptor (metadata) instead of Index (runtime)
/// - Supports all upper layers (record-layer, graph-layer, document-layer)
///
/// **Example usage**:
/// ```swift
/// let schema = Schema(
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
    public struct Version: Sendable, Hashable, Codable, CustomStringConvertible {
        public let major: Int
        public let minor: Int
        public let patch: Int

        /// Create a version
        ///
        /// - Parameters:
        ///   - major: Major version
        ///   - minor: Minor version
        ///   - patch: Patch version
        public init(_ major: Int, _ minor: Int, _ patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        public var description: String {
            return "\(major).\(minor).\(patch)"
        }

        // Codable
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.major = try container.decode(Int.self, forKey: .major)
            self.minor = try container.decode(Int.self, forKey: .minor)
            self.patch = try container.decode(Int.self, forKey: .patch)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(major, forKey: .major)
            try container.encode(minor, forKey: .minor)
            try container.encode(patch, forKey: .patch)
        }

        private enum CodingKeys: String, CodingKey {
            case major, minor, patch
        }
    }

    // MARK: - Entity

    /// Entity metadata (type-independent, Codable)
    ///
    /// Represents the complete schema definition for a Persistable type.
    /// Designed after SwiftData's `Schema.Entity` — Entity IS the metadata.
    ///
    /// **Codable properties**: name, fields, directoryComponents, indexes, enumMetadata
    /// **Runtime-only properties**: persistableType, indexDescriptors
    ///
    /// **Usage**:
    /// - Runtime: `Entity(from: User.self)` — full metadata + runtime type
    /// - Wire/CLI: `JSONDecoder().decode(Entity.self, from: data)` — metadata only
    public struct Entity: Sendable, Codable, Equatable, Hashable {

        // MARK: - Codable Properties

        /// Entity name (same as Persistable.persistableType)
        public let name: String

        /// Field metadata (name, type, field number, optionality, array)
        public let fields: [FieldSchema]

        /// Directory path components (static paths and dynamic field references)
        public let directoryComponents: [DirectoryComponentCatalog]

        /// Index definitions (type-erased, Codable)
        public let indexes: [AnyIndexDescriptor]

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
        /// Used by FDBRuntime to:
        /// - Create typed IndexMaintainers during migrations
        /// - Access directory path components at runtime
        /// - Check Polymorphable conformance
        ///
        /// nil when Entity is decoded from wire (no compiled type available)
        public var persistableType: (any Persistable.Type)?

        /// Typed index descriptors (runtime only, requires KeyPath)
        ///
        /// Empty when Entity is decoded from wire.
        public var indexDescriptors: [IndexDescriptor]

        // MARK: - Custom Codable (exclude runtime fields)

        private enum CodingKeys: String, CodingKey {
            case name, fields, directoryComponents, indexes, enumMetadata
            case ontologyClassIRI, objectPropertyIRI, objectPropertyFromField, objectPropertyToField
            case dataPropertyIRIs
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            self.fields = try container.decode([FieldSchema].self, forKey: .fields)
            self.directoryComponents = try container.decode([DirectoryComponentCatalog].self, forKey: .directoryComponents)
            self.indexes = try container.decode([AnyIndexDescriptor].self, forKey: .indexes)
            self.enumMetadata = try container.decode([String: [String]].self, forKey: .enumMetadata)
            self.ontologyClassIRI = try container.decodeIfPresent(String.self, forKey: .ontologyClassIRI)
            self.objectPropertyIRI = try container.decodeIfPresent(String.self, forKey: .objectPropertyIRI)
            self.objectPropertyFromField = try container.decodeIfPresent(String.self, forKey: .objectPropertyFromField)
            self.objectPropertyToField = try container.decodeIfPresent(String.self, forKey: .objectPropertyToField)
            self.dataPropertyIRIs = try container.decodeIfPresent([String].self, forKey: .dataPropertyIRIs)
            self.persistableType = nil
            self.indexDescriptors = []
        }

        // MARK: - Computed Properties

        /// All field names
        public var allFields: [String] {
            fields.map(\.name)
        }

        /// Build field name → FieldSchema map (for Encoder)
        public var fieldMapByName: [String: FieldSchema] {
            Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })
        }

        /// Build field number → FieldSchema map (for Decoder)
        public var fieldMapByNumber: [Int: FieldSchema] {
            Dictionary(uniqueKeysWithValues: fields.map { ($0.fieldNumber, $0) })
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
        public init(from type: any Persistable.Type) {
            self.name = type.persistableType
            self.fields = type.fieldSchemas
            self.directoryComponents = Self.extractDirectoryComponents(from: type)
            self.indexes = type.indexDescriptors.map { AnyIndexDescriptor($0) }
            self.enumMetadata = Self.extractEnumMetadata(from: type)
            self.ontologyClassIRI = Self.extractOntologyClassIRI(from: type)
            let objPropInfo = Self.extractObjectPropertyInfo(from: type)
            self.objectPropertyIRI = objPropInfo?.iri
            self.objectPropertyFromField = objPropInfo?.fromField
            self.objectPropertyToField = objPropInfo?.toField
            self.dataPropertyIRIs = Self.extractDataPropertyIRIs(from: type)
            self.persistableType = type
            self.indexDescriptors = type.indexDescriptors
        }

        // MARK: - Init: manual / decoded from wire

        /// Manual initializer (for testing, CLI, or decoded from wire)
        public init(
            name: String,
            fields: [FieldSchema],
            directoryComponents: [DirectoryComponentCatalog] = [],
            indexes: [AnyIndexDescriptor] = [],
            enumMetadata: [String: [String]] = [:],
            ontologyClassIRI: String? = nil,
            objectPropertyIRI: String? = nil,
            objectPropertyFromField: String? = nil,
            objectPropertyToField: String? = nil,
            dataPropertyIRIs: [String]? = nil
        ) {
            self.name = name
            self.fields = fields
            self.directoryComponents = directoryComponents
            self.indexes = indexes
            self.enumMetadata = enumMetadata
            self.ontologyClassIRI = ontologyClassIRI
            self.objectPropertyIRI = objectPropertyIRI
            self.objectPropertyFromField = objectPropertyFromField
            self.objectPropertyToField = objectPropertyToField
            self.dataPropertyIRIs = dataPropertyIRIs
            self.persistableType = nil
            self.indexDescriptors = []
        }

        // MARK: - Custom Equatable (compare only Codable fields)

        public static func == (lhs: Entity, rhs: Entity) -> Bool {
            lhs.name == rhs.name &&
            lhs.fields == rhs.fields &&
            lhs.directoryComponents == rhs.directoryComponents &&
            lhs.indexes == rhs.indexes &&
            lhs.enumMetadata == rhs.enumMetadata &&
            lhs.ontologyClassIRI == rhs.ontologyClassIRI &&
            lhs.objectPropertyIRI == rhs.objectPropertyIRI &&
            lhs.objectPropertyFromField == rhs.objectPropertyFromField &&
            lhs.objectPropertyToField == rhs.objectPropertyToField &&
            lhs.dataPropertyIRIs == rhs.dataPropertyIRIs
        }

        // MARK: - Custom Hashable (hash only Codable fields)

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(fields)
            hasher.combine(directoryComponents)
            hasher.combine(indexes)
            hasher.combine(enumMetadata)
            hasher.combine(ontologyClassIRI)
            hasher.combine(objectPropertyIRI)
            hasher.combine(objectPropertyFromField)
            hasher.combine(objectPropertyToField)
            hasher.combine(dataPropertyIRIs)
        }

        // MARK: - Private Helpers

        private static func extractDirectoryComponents(from type: any Persistable.Type) -> [DirectoryComponentCatalog] {
            let components = type.directoryPathComponents
            let fieldNames = type.directoryFieldNames
            var fieldNameIndex = 0
            return components.map { component -> DirectoryComponentCatalog in
                if let path = component as? Path {
                    return .staticPath(path.value)
                } else if component is any DynamicDirectoryElement {
                    let name = fieldNameIndex < fieldNames.count ? fieldNames[fieldNameIndex] : "unknown"
                    fieldNameIndex += 1
                    return .dynamicField(fieldName: name)
                } else {
                    return .staticPath("_unknown")
                }
            }
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

    /// Former indexes (schema evolution)
    /// Records of deleted indexes (schema definition only)
    public let formerIndexes: [String: FormerIndex]

    /// Index descriptors (metadata only)
    public let indexDescriptors: [IndexDescriptor]

    /// Indexes by name for quick lookup
    internal let indexDescriptorsByName: [String: IndexDescriptor]

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
    /// let schema = Schema([User.self, Order.self])  // Indexes auto-collected
    /// ```
    public init(
        _ types: [any Persistable.Type],
        version: Version = Version(1, 0, 0),
        indexDescriptors: [IndexDescriptor] = []
    ) {
        self.version = version
        self.encodingVersion = version

        // Build entities
        var entities: [Entity] = []
        var entitiesByName: [String: Entity] = [:]

        for type in types {
            let entity = Entity(from: type)
            entities.append(entity)
            entitiesByName[entity.name] = entity
        }

        self.entities = entities
        self.entitiesByName = entitiesByName

        // Collect index descriptors from types
        var allIndexDescriptors: [IndexDescriptor] = []

        for type in types {
            // Get IndexDescriptors from type (generated by macros)
            let descriptors = type.indexDescriptors
            allIndexDescriptors.append(contentsOf: descriptors)
        }

        // Merge with manually provided descriptors
        allIndexDescriptors.append(contentsOf: indexDescriptors)

        // Store index descriptors with duplicate check
        self.indexDescriptors = allIndexDescriptors
        var indexDescriptorsByName: [String: IndexDescriptor] = [:]
        for descriptor in allIndexDescriptors {
            if let existing = indexDescriptorsByName[descriptor.name] {
                preconditionFailure(
                    "Duplicate index name '\(descriptor.name)' detected. " +
                    "Existing index keyPaths: \(existing.keyPaths), " +
                    "duplicate index keyPaths: \(descriptor.keyPaths). " +
                    "Index names must be unique across all entities in the schema."
                )
            }
            indexDescriptorsByName[descriptor.name] = descriptor
        }
        self.indexDescriptorsByName = indexDescriptorsByName

        // Former indexes (empty for now, future: migration support)
        self.formerIndexes = [:]
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
    ) {
        self.version = version
        self.encodingVersion = version

        // Build entity maps
        var entitiesByName: [String: Entity] = [:]
        for entity in entities {
            entitiesByName[entity.name] = entity
        }

        self.entities = entities
        self.entitiesByName = entitiesByName

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
                preconditionFailure(
                    "Duplicate index name '\(descriptor.name)' detected. " +
                    "Existing index keyPaths: \(existing.keyPaths), " +
                    "duplicate index keyPaths: \(descriptor.keyPaths). " +
                    "Index names must be unique across all entities in the schema."
                )
            }
            indexDescriptorsByName[descriptor.name] = descriptor
        }
        self.indexDescriptorsByName = indexDescriptorsByName

        // Former indexes (empty for test schemas)
        self.formerIndexes = [:]
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
        return lhsNames == rhsNames
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
    }
}

// MARK: - Schema.Version Comparable

extension Schema.Version: Comparable {
    public static func < (lhs: Schema.Version, rhs: Schema.Version) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}

// MARK: - FormerIndex

/// Former index metadata (for schema evolution)
///
/// Records when an index was added and removed, helping with
/// schema migration and backward compatibility.
public struct FormerIndex: Sendable, Hashable, Equatable {
    /// Index name
    public let name: String

    /// Version when the index was originally added
    public let addedVersion: Schema.Version

    /// Timestamp when the index was removed (seconds since epoch)
    public let removedTimestamp: Double

    public init(
        name: String,
        addedVersion: Schema.Version,
        removedTimestamp: Double
    ) {
        self.name = name
        self.addedVersion = addedVersion
        self.removedTimestamp = removedTimestamp
    }
}

// MARK: - SchemaError

/// Errors that can occur during Schema validation
public enum SchemaError: Error, CustomStringConvertible, Sendable {
    /// Duplicate index name detected across entities
    ///
    /// Index names must be unique across all entities in a schema.
    /// This error provides details about both the existing and duplicate index.
    case duplicateIndexName(indexName: String, existingKeyPaths: [String], duplicateKeyPaths: [String])

    public var description: String {
        switch self {
        case .duplicateIndexName(let indexName, let existingKeyPaths, let duplicateKeyPaths):
            let existingDesc = existingKeyPaths.joined(separator: ", ")
            let duplicateDesc = duplicateKeyPaths.joined(separator: ", ")
            return "Duplicate index name '\(indexName)' detected. " +
                   "Existing index keyPaths: [\(existingDesc)], " +
                   "duplicate index keyPaths: [\(duplicateDesc)]. " +
                   "Index names must be unique across all entities in the schema."
        }
    }
}

// MARK: - Schema Validation

extension Schema {
    /// Validate the schema for duplicate index names
    ///
    /// This method checks that all index names are unique across the entire schema,
    /// including both entity-defined indexes and manually added indexes.
    ///
    /// **Note**: As of the current implementation, Schema initializer already enforces
    /// unique index names via `preconditionFailure`. This method is kept for:
    /// 1. Explicit validation in migration contexts
    /// 2. Programmatic error handling (throws instead of crashing)
    ///
    /// **Usage**:
    /// ```swift
    /// let schema = Schema([User.self, Order.self])
    /// try schema.validateIndexNames()  // Throws if duplicates found
    /// ```
    ///
    /// - Throws: `SchemaError.duplicateIndexName` if duplicate index names are detected
    public func validateIndexNames() throws {
        var seenIndexes: [String: IndexDescriptor] = [:]

        // Check ALL indexDescriptors (includes both entity-defined and manual indexes)
        for descriptor in indexDescriptors {
            if let existing = seenIndexes[descriptor.name] {
                throw SchemaError.duplicateIndexName(
                    indexName: descriptor.name,
                    existingKeyPaths: existing.keyPaths.map { String(describing: $0) },
                    duplicateKeyPaths: descriptor.keyPaths.map { String(describing: $0) }
                )
            }
            seenIndexes[descriptor.name] = descriptor
        }
    }
}
