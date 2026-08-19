import DatabaseTypes
/// VersionedSchema - Protocol for defining schema versions
///
/// **Design**: Each schema version is represented as a type conforming to this protocol.
/// This enables type-safe schema evolution with compile-time checks.
///
/// **Example usage**:
/// ```swift
/// enum AppSchemaV1: VersionedSchema {
///     static let versionIdentifier = Schema.Version(1, 0, 0)
///     static var entities: [Schema.Entity] {
///         get throws(SchemaEntityError) {
///             [try User.schemaEntity, try Order.schemaEntity]
///         }
///     }
///
///     @Persistable
///     struct User {
///         var id: String
///         var name: String
///         var email: String
///
///         #Index(.ordered(
///             name: "users_by_email",
///             keys: [.ascending(\User.email)],
///             unique: true
///         ))
///     }
///
///     @Persistable
///     struct Order {
///         var id: String
///         var userId: String
///         var total: Double
///     }
/// }
///
/// enum AppSchemaV2: VersionedSchema {
///     static let versionIdentifier = Schema.Version(2, 0, 0)
///     static var entities: [Schema.Entity] {
///         get throws(SchemaEntityError) {
///             [try User.schemaEntity, try Order.schemaEntity]
///         }
///     }
///
///     @Persistable
///     struct User {
///         var id: String
///         var name: String
///         var email: String
///         var age: Int32 = 0  // New field
///
///         #Index(.ordered(
///             name: "users_by_email",
///             keys: [.ascending(\User.email)],
///             unique: true
///         ))
///         #Index(.ordered(
///             name: "users_by_age",
///             keys: [.ascending(\User.age)]
///         ))
///     }
///
///     // Order unchanged, can be re-exported
///     typealias Order = AppSchemaV1.Order
/// }
///
/// // Type alias for current schema
/// typealias User = AppSchemaV2.User
/// typealias Order = AppSchemaV2.Order
/// ```
public protocol VersionedSchema: Sendable {
    /// Schema version identifier
    ///
    /// Uniquely identifies this schema version using semantic versioning.
    static var versionIdentifier: Schema.Version { get }

    /// Static entity declarations included in this schema version.
    ///
    /// List all model schemas that exist in this schema version.
    /// Order doesn't matter for functionality, but consistent ordering
    /// helps with debugging and migration comparisons.
    static var entities: [Schema.Entity] {
        get throws(SchemaEntityError)
    }

    /// Materializes the immutable schema represented by this version.
    static func makeSchema() throws(SchemaError) -> Schema

    /// All concrete index declarations in this version.
    static var allIndexDescriptors: [IndexDescriptor] {
        get throws(SchemaError)
    }

    /// All concrete and polymorphic index names in this version.
    static var indexNames: Set<String> {
        get throws(SchemaError)
    }

    /// Computes the index transition from another version.
    static func indexChanges(
        from other: any VersionedSchema.Type
    ) throws(SchemaError) -> [IndexChange]

    /// Computes polymorphic-index transitions from another version.
    static func polymorphicIndexChanges(
        from other: any VersionedSchema.Type
    ) throws(SchemaError) -> [PolymorphicIndexChange]

    /// Determines whether migration from another version is metadata-only.
    static func canLightweightMigrate(
        from other: any VersionedSchema.Type
    ) throws(SchemaError) -> Bool
}

// MARK: - VersionedSchema Extensions

extension VersionedSchema {
    /// Create a Schema instance from this VersionedSchema
    ///
    /// Converts the protocol type to a concrete schema consumed by the
    /// configured database runtime.
    ///
    /// - Returns: Schema instance with version and models
    public static func makeSchema() throws(SchemaError) -> Schema {
        let compiledEntities: [Schema.Entity]
        do {
            compiledEntities = try entities
        } catch let error {
            throw .invalidEntity(error)
        }
        return try Schema(
            entities: compiledEntities,
            version: versionIdentifier
        )
    }

    /// Get all concrete index descriptors from models in this schema version.
    ///
    /// Polymorphic logical indexes are exposed through `indexNames` because
    /// they do not have a single concrete `IndexDescriptor`.
    ///
    /// - Returns: Array of all index descriptors
    public static var allIndexDescriptors: [IndexDescriptor] {
        get throws(SchemaError) {
            try makeSchema().indexDescriptors
        }
    }

    /// Get all index names from this schema version
    ///
    /// - Returns: Set of index names
    public static var indexNames: Set<String> {
        get throws(SchemaError) {
            try makeSchema().allIndexNames
        }
    }
}

// MARK: - Schema Comparison Helpers

extension VersionedSchema {
    /// Compare concrete indexes between two schema versions.
    ///
    /// Logical polymorphic declarations are returned separately by
    /// `polymorphicIndexChanges(from:)`.
    ///
    /// - Parameter other: Another VersionedSchema type
    /// - Returns: Added, removed, and replaced concrete declarations.
    public static func indexChanges(
        from other: any VersionedSchema.Type
    ) throws(SchemaError) -> [IndexChange] {
        try makeSchema().indexChanges(from: other.makeSchema())
    }

    public static func polymorphicIndexChanges(
        from other: any VersionedSchema.Type
    ) throws(SchemaError) -> [PolymorphicIndexChange] {
        try makeSchema().polymorphicIndexChanges(
            from: other.makeSchema()
        )
    }

    /// Check if migration from another schema is a "lightweight" migration
    ///
    /// A lightweight migration only involves index additions/removals and
    /// field additions (with defaults). No data transformation is needed.
    ///
    /// - Parameter other: Previous schema version
    /// - Returns: true if lightweight migration is possible
    public static func canLightweightMigrate(
        from other: any VersionedSchema.Type
    ) throws(SchemaError) -> Bool {
        let report = try makeSchema().compatibilityReport(from: other.makeSchema())
        return report.isLightweightCompatible
    }
}
