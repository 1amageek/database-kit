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
///     static let models: [any Persistable.Type] = [User.self, Order.self]
///
///     @Persistable
///     struct User {
///         var id: String
///         var name: String
///         var email: String
///
///         #Index(ScalarIndexKind<User>(fields: [\.email]), unique: true)
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
///     static let models: [any Persistable.Type] = [User.self, Order.self]
///
///     @Persistable
///     struct User {
///         var id: String
///         var name: String
///         var email: String
///         var age: Int32 = 0  // New field
///
///         #Index(ScalarIndexKind<User>(fields: [\.email]), unique: true)
///         #Index(ScalarIndexKind<User>(fields: [\.age]))  // New index
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

    /// Persistable types included in this schema version
    ///
    /// List all model types that exist in this schema version.
    /// Order doesn't matter for functionality, but consistent ordering
    /// helps with debugging and migration comparisons.
    static var models: [any Persistable.Type] { get }
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
        try Schema(models, version: versionIdentifier)
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
    /// Compare indexes between two schema versions
    ///
    /// Returns the differences in indexes between this schema and another.
    ///
    /// - Parameter other: Another VersionedSchema type
    /// - Returns: Tuple of (added indexes, removed indexes)
    public static func indexChanges(
        from other: any VersionedSchema.Type
    ) throws(SchemaError) -> (added: Set<String>, removed: Set<String>) {
        let currentIndexes = try Self.indexNames
        let otherIndexes = try other.indexNames

        let added = currentIndexes.subtracting(otherIndexes)
        let removed = otherIndexes.subtracting(currentIndexes)

        return (added: added, removed: removed)
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
