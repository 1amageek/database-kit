import DatabaseTypes
// Polymorphable.swift
// Core - Protocol for polymorphic type groups
//
// Enables multiple Persistable types to share a directory and indexes,
// allowing them to be queried together via a common protocol.


/// Polymorphable protocol - Defines a group of persistable types that share storage
///
/// When a protocol inherits from `Polymorphable` and is annotated with
/// `@Polymorphable`, the protocol becomes a polymorphic storage group with:
/// - Shared directory/subspace for all conforming types
/// - Shared indexes across all conforming types
/// - Polymorphic queries returning multiple types
///
/// `@Polymorphable` generates group metadata and should validate the protocol
/// declaration. It cannot add `Polymorphable` inheritance to the protocol,
/// because Swift does not allow `extension SomeProtocol: OtherProtocol`.
///
/// **Platform Support**:
/// - Client: Protocol definitions and metadata
/// - Runtime: Full persistence through database-framework
///
/// **Usage**:
/// ```swift
/// @Polymorphable
/// @PolymorphicDirectory("app", "documents")
/// @PolymorphicIndex(
///     .scalar,
///     fields: ["title"],
///     name: "Document_title"
/// )
/// protocol Document: Polymorphable<DocumentPolymorphicGroup> {
///     var id: String { get }
///     var title: String { get }
/// }
///
/// @Persistable
/// struct Article: Document {
///     var id: String
///     var title: String
///     var content: String
///
///     #Directory<Article>("app", "articles")  // Optional: type-specific directory
/// }
///
/// @Persistable
/// struct Report: Document {
///     var id: String
///     var title: String
///     var data: ByteString
///     // No #Directory: uses default [.staticPath("Report")]
/// }
/// ```
///
/// **Property Access**:
/// ```swift
/// // Type-specific (from Persistable / @Persistable)
/// Article.directoryPathComponents  // ["app", "articles"]
/// Report.directoryPathComponents   // ["Report"] (default)
///
/// // Polymorphic shared (from Polymorphable / @Polymorphable)
/// Article.polymorphicDirectoryPathComponents  // ["app", "documents"]
/// Report.polymorphicDirectoryPathComponents   // ["app", "documents"]
/// ```
///
/// **Dual-Write Behavior**:
/// When a type has both `directoryPathComponents` and `polymorphicDirectoryPathComponents`:
/// - If they differ: data is written to both directories
/// - If they are the same: data is written once
///
/// **Storage Layout**:
/// ```
/// [polymorphicDirectory]/R/[typeCode]/[id] → canonical persisted fields
/// [polymorphicDirectory]/I/[indexName]/[values]/[typeCode]/[id] → empty
/// ```
///
/// The `typeCode` is a deterministic Int64 hash of the type name,
/// ensuring stable identification across restarts.
///
/// **Static Schema Construction**:
/// ```swift
/// let schema = try Schema(
///     entities: [
///         try Article.schemaEntity,
///         try Report.schemaEntity
///     ]
/// )
/// ```
public protocol Polymorphable<Group>: Sendable {
    /// Concrete metadata declaration generated for the annotated group.
    associatedtype Group: PolymorphicGroupDeclaration
}

// MARK: - Default Implementations

public extension Polymorphable {
    /// Stable identifier for this polymorphic group.
    static var polymorphableType: String { Group.identifier }

    /// Shared storage directory for this polymorphic group.
    static var polymorphicDirectoryPathComponents: [DirectoryPathComponent] {
        Group.directoryComponents
    }

    /// Directory policy for the shared storage directory.
    static var polymorphicDirectoryLayer: DirectoryLayer {
        Group.directoryLayer
    }

    /// Logical indexes shared by every concrete model in this group.
    static var polymorphicIndexes: [PolymorphicIndexDefinition] {
        Group.indexes
    }
}

public extension Persistable where Self: Polymorphable {
    static var polymorphicMembership: PolymorphicMembership? {
        PolymorphicMembership(
            identifier: polymorphableType,
            directoryComponents: polymorphicDirectoryPathComponents,
            directoryLayer: polymorphicDirectoryLayer,
            indexes: polymorphicIndexes
        )
    }
}

// MARK: - Type Code Generation

public extension Polymorphable {
    /// Generate a deterministic type code for a type name
    ///
    /// Uses DJB2 hash algorithm for consistent, collision-resistant codes.
    /// The result is always positive (mask off sign bit).
    ///
    /// - Parameter typeName: The persistableType of a conforming type
    /// - Returns: Deterministic Int64 type code
    static func typeCode(for typeName: String) -> Int64 {
        var hash: UInt64 = 5381
        for char in typeName.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }
        // Ensure positive by masking off sign bit
        return Int64(hash & 0x7FFFFFFFFFFFFFFF)
    }
}
