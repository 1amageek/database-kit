// Polymorphable.swift
// Core - Protocol for polymorphic type groups
//
// Enables multiple Persistable types to share a directory and indexes,
// allowing them to be queried together via a common protocol.

import Foundation

/// Polymorphable protocol - Defines a group of persistable types that share storage
///
/// When applied to a protocol via `@Polymorphable` macro, enables:
/// - Shared directory/subspace for all conforming types
/// - Shared indexes across all conforming types
/// - Polymorphic queries returning multiple types
///
/// **Platform Support**:
/// - Client (iOS/macOS): Protocol definitions, metadata
/// - Server (macOS/Linux): Full persistence with FDBRuntime
///
/// **Usage**:
/// ```swift
/// @Polymorphable
/// protocol Document: Polymorphable {
///     var id: String { get }
///     var title: String { get }
///
///     #Directory<Document>("app", "documents")
///     #Index<Document>(ScalarIndexKind(fields: [\.title]), name: "Document_title")
/// }
///
/// @Persistable
/// struct Article: Document {
///     var id: String = ULID().ulidString
///     var title: String
///     var content: String
///
///     #Directory<Article>("app", "articles")  // Optional: type-specific directory
/// }
///
/// @Persistable
/// struct Report: Document {
///     var id: String = ULID().ulidString
///     var title: String
///     var data: Data
///     // No #Directory: uses default [Path("Report")]
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
/// [polymorphicDirectory]/R/[typeCode]/[id] → protobuf
/// [polymorphicDirectory]/I/[indexName]/[values]/[typeCode]/[id] → empty
/// ```
///
/// The `typeCode` is a deterministic Int64 hash of the type name,
/// ensuring stable identification across restarts.
///
/// **Swift Type System Limitation**:
/// Protocol types cannot be passed to generic functions requiring `Polymorphable`:
/// ```swift
/// // ❌ Compile error: 'any Document' cannot conform to 'Polymorphable'
/// try await context.fetchPolymorphic(Document.self)
///
/// // ✅ Use any concrete conforming type (all share the same polymorphic directory)
/// try await context.fetchPolymorphic(Article.self)
/// // Returns [any Persistable] containing all conforming types
/// ```
public protocol Polymorphable: Sendable {
    // MARK: - Type Metadata

    /// Unique identifier for this polymorphic group
    ///
    /// Typically the protocol name (e.g., "Document").
    /// Used for identifying which polymorphic group a type belongs to.
    static var polymorphableType: String { get }

    // MARK: - Polymorphic Directory Metadata

    /// Directory path components for polymorphic shared storage
    ///
    /// All conforming types are stored under this directory for polymorphic queries.
    /// Generated from `#Directory<P>` macro in the protocol body.
    ///
    /// **Example**:
    /// ```swift
    /// #Directory<Document>("app", "documents")
    /// // → [Path("app"), Path("documents")]
    /// ```
    ///
    /// **Note**: Polymorphic protocols cannot use dynamic `Field` components
    /// since they don't have instance values.
    static var polymorphicDirectoryPathComponents: [any DirectoryPathElement] { get }

    /// Directory layer type for polymorphic shared storage
    ///
    /// Generated from `#Directory<P>` macro's `layer:` parameter.
    static var polymorphicDirectoryLayer: DirectoryLayer { get }

    // MARK: - Polymorphic Index Metadata

    /// Index descriptors shared across all conforming types
    ///
    /// Generated from `#Index<P>` macro declarations in the protocol body.
    /// These indexes span all conforming types and are stored in the polymorphic directory.
    ///
    /// **Example**:
    /// ```swift
    /// #Index<Document>(ScalarIndexKind(fields: [\.title]), name: "Document_title")
    /// ```
    ///
    /// **Note**: Index fields must be properties defined in the protocol.
    static var polymorphicIndexDescriptors: [IndexDescriptor] { get }
}

// MARK: - Default Implementations

public extension Polymorphable {
    /// Default implementation returns empty array (no polymorphic indexes)
    static var polymorphicIndexDescriptors: [IndexDescriptor] { [] }

    /// Default implementation returns `.default` layer
    static var polymorphicDirectoryLayer: DirectoryLayer { .default }

    /// Default implementation uses polymorphableType as directory
    static var polymorphicDirectoryPathComponents: [any DirectoryPathElement] {
        [Path(polymorphableType)]
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
