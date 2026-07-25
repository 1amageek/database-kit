import DatabaseTypes
/// @Persistable macro declaration
///
/// Generates Persistable protocol conformance and static model metadata.
///
/// **Supports all data model layers**:
/// - Entity layer (RDB): Structured entities with indexes
/// - DocumentLayer (DocumentDB): Flexible documents
/// - VectorLayer (Vector search): Use `#Index(.vector(...))`
/// - GraphLayer (GraphDB): Define nodes and edges with relationships
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct User {
///     var id: String
///
///     #Directory<User>("users")
///     #Index(.scalar, fields: [\User.email], unique: true)
///
///     var email: String
///     var name: String
/// }
/// ```
///
/// **With custom type name** (for renaming stability):
/// ```swift
/// @Persistable(type: "User")
/// struct Member {
///     var id: String
///     var name: String
/// }
/// // persistableType = "User" (not "Member")
/// ```
///
/// **Generated code**:
/// - `static var persistableType: String`
/// - `static var allFields: [String]`
/// - `static var indexDescriptors: [IndexDescriptor]`
/// - `static func fieldNumber(for fieldName: String) -> Int?`
/// - `static func enumMetadata(for fieldName: String) -> EnumMetadata?`
/// - `init(...)`
@attached(member, names: named(persistableType), named(allFields), named(fields), named(Fields), named(_persistableIndexDescriptors), named(indexDescriptors), named(relationshipDescriptors), named(owlObjectPropertyDescriptors), named(directoryPathComponents), named(directoryLayer), named(fieldNumber), named(enumMetadata), named(init), arbitrary)
@attached(extension, conformances: Persistable, Sendable)
public macro Persistable() = #externalMacro(module: "DatabaseKitMacros", type: "PersistableMacro")

/// @Persistable macro with custom type name
///
/// **Usage**:
/// ```swift
/// @Persistable(type: "User")
/// struct Member {
///     var id: String
///     var name: String
/// }
/// // persistableType = "User"
/// ```
@attached(member, names: named(persistableType), named(allFields), named(fields), named(Fields), named(_persistableIndexDescriptors), named(indexDescriptors), named(relationshipDescriptors), named(owlObjectPropertyDescriptors), named(directoryPathComponents), named(directoryLayer), named(fieldNumber), named(enumMetadata), named(init), arbitrary)
@attached(extension, conformances: Persistable, Sendable)
public macro Persistable(type: String) = #externalMacro(module: "DatabaseKitMacros", type: "PersistableMacro")

/// Resolves a stored-property key path to its generated typed field.
///
/// The key path is consumed by the compiler plugin. The expanded program stores
/// only the field's stable schema identity.
@freestanding(expression)
public macro `field`<Root, Value>(
    _ keyPath: KeyPath<Root, Value>
) -> Field<Root, Value> = #externalMacro(
    module: "DatabaseKitMacros",
    type: "FieldExpressionMacro"
)

/// #Index macro declaration
///
/// Declares built-in index semantics and source-level field selections.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Product {
///     var id: String
///
///     // Scalar index for sorting and range queries
///     #Index(.scalar, fields: [\Product.email], unique: true)
///     #Index(
///         .scalar,
///         fields: [\Product.category, \Product.price]
///     )
///
///     // Aggregation indexes
///     #Index(.count, groupBy: [\Product.category])
///     #Index(
///         .sum,
///         groupBy: [\Product.category],
///         value: \Product.price
///     )
///
///     var email: String
///     var category: String
///     var price: Int64
/// }
/// ```
///
/// This is a marker macro. The @Persistable macro reads the #Index declaration
/// and generates the indexDescriptors array.
///
/// The attached model macro validates field roles, generates stable field
/// identities, and constructs key-path-free descriptors.
/// - Scalar definition: `{TypeName}_{field1}_{field2}`
/// - Count definition: `{TypeName}_count_{field1}_{field2}`
/// - Sum definition: `{TypeName}_sum_{groupFields}_{valueField}`
///
/// **How it works**:
/// 1. The declaration macro reads the source KeyPath literals.
/// 2. `@Persistable` emits model-scoped `Field` identities.
/// 3. Runtime metadata retains field identities, never KeyPaths.
@freestanding(declaration)
public macro Index(
    _ definition: IndexDefinition,
    fields: [AnyKeyPath] = [],
    groupBy: [AnyKeyPath] = [],
    value: AnyKeyPath? = nil,
    field: AnyKeyPath? = nil,
    embedding: AnyKeyPath? = nil,
    location: AnyKeyPath? = nil,
    from: AnyKeyPath? = nil,
    edge: AnyKeyPath? = nil,
    to: AnyKeyPath? = nil,
    graph: AnyKeyPath? = nil,
    orders: [IndexFieldOrder] = [],
    storedFields: [AnyKeyPath] = [],
    unique: Bool = false,
    name: String? = nil
) = #externalMacro(module: "DatabaseKitMacros", type: "IndexMacro")

/// Declares a protocol-level logical index for `@Polymorphable`.
///
/// Swift cannot resolve `\Self.member` in a freestanding macro while the
/// protocol itself is still being defined. The attached macro validates these
/// names against protocol properties, and `Schema` validates their concrete
/// field types and identities for every conforming model.
@freestanding(declaration)
public macro PolymorphicIndex(
    _ definition: IndexDefinition,
    fields: [String] = [],
    groupBy: [String] = [],
    value: String? = nil,
    field: String? = nil,
    embedding: String? = nil,
    location: String? = nil,
    from: String? = nil,
    edge: String? = nil,
    to: String? = nil,
    graph: String? = nil,
    orders: [IndexFieldOrder] = [],
    storedFields: [String] = [],
    unique: Bool = false,
    name: String? = nil
) = #externalMacro(module: "DatabaseKitMacros", type: "IndexMacro")

/// #Directory macro declaration
///
/// Declares the logical directory path for a persistable type.
///
/// **Usage**:
/// ```swift
/// #Directory<User>("app", "users")
/// #Directory<Order>("tenants", \Order.tenantID, "orders", layer: .partition)
/// ```
///
/// This macro validates and emits directory metadata. The database runtime
/// resolves that declaration through its configured storage backend.
@freestanding(declaration)
public macro Directory<T>(_ elements: Any..., layer: DirectoryLayer = .default) = #externalMacro(module: "DatabaseKitMacros", type: "DirectoryMacro")

/// Directory layer type
///
/// Used by #Directory macro to specify the directory layer type.
public enum DirectoryLayer: String, Sendable, Hashable {
    /// Default directory
    case `default` = "default"

    /// Multi-tenant partition (requires at least one Field in path)
    case partition = "partition"
}

// MARK: - @Polymorphable Macro

/// @Polymorphable macro declaration
///
/// Generates polymorphic group metadata for a protocol definition. Enables
/// multiple Persistable types to share a directory and indexes, allowing them to
/// be queried together.
///
/// **Usage**:
/// ```swift
/// @Polymorphable
/// protocol Document: Polymorphable {  // Required: macros cannot add protocol inheritance
///     var id: String { get }
///     var title: String { get }
///     var updatedAt: Timestamp { get }
///
///     #Directory<Self>("app", "documents")
///     #PolymorphicIndex(
///         .scalar,
///         fields: ["title"],
///         name: "Document_title"
///     )
/// }
///
/// @Persistable
/// struct Article: Document {
///     var id: String
///     var title: String
///     var updatedAt: Timestamp
///     var content: String
/// }
///
/// @Persistable
/// struct Report: Document {
///     var id: String
///     var title: String
///     var updatedAt: Timestamp
///     var data: ByteString
/// }
/// ```
///
/// **Important**: The protocol must explicitly inherit from `Polymorphable`.
/// Swift does not allow an attached macro on a protocol to add protocol
/// inheritance by generating `extension Document: Polymorphable`.
/// The macro generates default implementations for the protocol requirements
/// and should validate that the declaration is a valid polymorphic group.
///
/// **Generated code**:
/// - `static var polymorphableType: String` - Protocol name identifier
/// - `static var polymorphicDirectoryPathComponents: [DirectoryPathComponent]` - Shared directory
/// - `static var polymorphicDirectoryLayer: DirectoryLayer` - Directory layer type
/// - `static var polymorphicIndexes: [PolymorphicIndexDefinition]` - Shared indexes
///
/// **Server-side Usage**:
/// ```swift
/// let schema = try Schema(
///     entities: [
///         try Article.schemaEntity,
///         try Report.schemaEntity
///     ]
/// )
/// ```
///
/// **Dual-Write Behavior**:
/// When a conforming type has its own `#Directory` (different from the protocol's):
/// - Save: Data written to both type-specific AND polymorphic directories
/// - Delete: Data removed from both directories
///
/// **Swift Type System Note**:
/// Protocol types cannot be passed to generic functions requiring `Polymorphable`:
/// ```swift
/// // ❌ Compile error: 'any Document' cannot conform to 'Polymorphable'
/// try await context.fetchPolymorphic(Document.self)
///
/// // ✅ Use any concrete conforming type (all share the same polymorphic directory)
/// try await context.fetchPolymorphic(Article.self)
/// ```
///
/// **Storage Layout**:
/// All conforming types share the same directory with type code prefix:
/// ```
/// [polymorphic-directory]/R/[typeCode]/[id] → canonical persisted fields
/// [type-directory]/R/[PersistableType]/[id] → canonical persisted fields (if dual-write)
/// ```
@attached(member, names: named(polymorphableType), named(polymorphicDirectoryPathComponents), named(polymorphicDirectoryLayer), named(polymorphicIndexes))
@attached(extension, names: named(polymorphableType), named(polymorphicDirectoryPathComponents), named(polymorphicDirectoryLayer), named(polymorphicIndexes))
public macro Polymorphable() = #externalMacro(module: "DatabaseKitMacros", type: "PolymorphableMacro")

// MARK: - @Transient Macro

/// @Transient macro declaration
///
/// Marks a property as transient (excluded from persistence and allFields).
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct User {
///     var id: String
///     var email: String
///     var name: String
///
///     @Transient
///     var cachedFullName: String?  // Not persisted to database
///
///     @Transient
///     var isOnline: Bool = false   // Runtime-only state
/// }
/// ```
///
/// **Effects**:
/// - Field is excluded from `allFields` array
/// - Field is excluded from canonical persistence
/// - Field is excluded from generated initializer
/// - Field is excluded from generated persistence traversal and schema metadata
///
/// **Requirements**:
/// - Field must have a default value (since it's excluded from initializer)
@attached(peer)
public macro Transient() = #externalMacro(module: "DatabaseKitMacros", type: "TransientMacro")

// MARK: - @Reference Macro (Test)

/// @Reference macro declaration - TEST for circular reference behavior
///
/// Tests if type references in macros cause circular dependency issues.
///
/// **Usage**:
/// ```swift
/// struct A {
///     @Reference(B.self)
///     var bId: String?
/// }
///
/// struct B {
///     @Reference(A.self)
///     var aId: String?
/// }
/// ```
@attached(peer)
public macro Reference<T>(_ type: T.Type) = #externalMacro(module: "DatabaseKitMacros", type: "ReferenceMacro")
