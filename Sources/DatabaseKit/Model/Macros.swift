import DatabaseTypes
/// @Persistable macro declaration
///
/// Generates persistence conformance for models and raw-value enums.
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
///     #Index(.ordered(
///         name: "users_by_email",
///         keys: [.ascending(\User.email)],
///         unique: true
///     ))
///
///     var email: String
///     var name: String
/// }
/// ```
///
/// Raw-value enums use the same attribute. String- and Int-backed enums receive
/// generated case enumeration plus the standard field-value and schema
/// metadata implementation.
///
/// ```swift
/// @Persistable
/// enum Status: String {
///     case active
///     case inactive
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
/// **Generated model code**:
/// - `typealias ID` inferred from the declared `id` property
/// - `static var persistableType: String`
/// - `static var allFields: [String]`
/// - `static var indexDescriptors: [IndexDescriptor]`
/// - `static func fieldNumber(for fieldName: String) -> Int?`
/// - `static func enumMetadata(for fieldName: String) -> EnumMetadata?`
/// - `init(...)`
@attached(member, names: named(persistableType), named(allFields), named(fields), named(Fields), named(_persistableIndexDescriptors), named(indexDescriptors), named(relationshipDescriptors), named(owlObjectPropertyDescriptors), named(directoryPathComponents), named(directoryLayer), named(fieldNumber), named(enumMetadata), named(init), arbitrary)
@attached(extension, conformances: Persistable, PersistableEnum)
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
///
/// The custom persisted type name applies only to model structs.
@attached(member, names: named(persistableType), named(allFields), named(fields), named(Fields), named(_persistableIndexDescriptors), named(indexDescriptors), named(relationshipDescriptors), named(owlObjectPropertyDescriptors), named(directoryPathComponents), named(directoryLayer), named(fieldNumber), named(enumMetadata), named(init), arbitrary)
@attached(extension, conformances: Persistable, PersistableEnum)
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
/// Declares one complete, explicitly named index value.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Product {
///     var id: String
///
///     #Index(
///         .ordered(
///             name: "products_by_email",
///             keys: [.ascending(\Product.email)],
///             unique: true
///         )
///     )
///     #Index(.ordered(
///         name: "products_by_category_and_price",
///         keys: [
///             .ascending(\Product.category),
///             .ascending(\Product.price),
///         ]
///     ))
///
///     // Aggregation indexes
///     #Index(.aggregate(
///         name: "product_count_by_category",
///         function: .count,
///         groupBy: [.ascending(\Product.category)]
///     ))
///     #Index(.aggregate(
///         name: "product_price_sum_by_category",
///         function: .sum,
///         groupBy: [.ascending(\Product.category)],
///         value: \Product.price
///     ))
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
/// The attached model macro validates the declaration name, rewrites source
/// key paths into stable field identities, and constructs a key-path-free
/// descriptor. Index names are always explicit persisted identities.
///
/// **How it works**:
/// 1. The declaration macro reads the source KeyPath literals.
/// 2. `@Persistable` emits model-scoped `Field` identities.
/// 3. Runtime metadata retains field identities, never KeyPaths.
@freestanding(declaration)
public macro Index(
    _ declaration: IndexDeclaration<AnyKeyPath>
) = #externalMacro(module: "DatabaseKitMacros", type: "IndexMacro")

/// Declares one logical index on an `@Polymorphable` protocol.
///
/// Swift cannot form `\Self.member` while the protocol itself is being
/// declared. Field names are therefore retained as logical references and
/// resolved against every concrete member when `Schema` is constructed.
@attached(peer)
public macro PolymorphicIndex(
    _ declaration: IndexDeclaration<String>
) = #externalMacro(
    module: "DatabaseKitMacros",
    type: "PolymorphicDeclarationMarkerMacro"
)

/// Declares the shared directory of an `@Polymorphable` protocol.
///
/// Protocol groups support static path components only. Dynamic partition
/// fields belong to concrete model directories where a stored-property key
/// path can be validated.
@attached(peer)
public macro PolymorphicDirectory(
    _ components: String...,
    layer: DirectoryLayer = .default
) = #externalMacro(
    module: "DatabaseKitMacros",
    type: "PolymorphicDeclarationMarkerMacro"
)

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
/// @PolymorphicDirectory("app", "documents")
/// @PolymorphicIndex(.ordered(
///     name: "Document_title",
///     keys: [.ascending("title")]
/// ))
/// protocol Document: Polymorphable<DocumentPolymorphicGroup> {
///     var id: String { get }
///     var title: String { get }
///     var updatedAt: Timestamp { get }
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
/// **Important**: The protocol must explicitly bind the concrete declaration
/// generated by the macro through
/// `Polymorphable<{ProtocolName}PolymorphicGroup>`. Keeping the same-type
/// constraint in the inheritance clause lets Swift validate every concrete
/// model's group membership without a runtime registry.
///
/// **Generated code**:
/// - `{ProtocolName}PolymorphicGroup` - Static group metadata
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
@attached(peer, names: suffixed(PolymorphicGroup))
public macro Polymorphable(identifier: String? = nil) =
    #externalMacro(module: "DatabaseKitMacros", type: "PolymorphableMacro")

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
