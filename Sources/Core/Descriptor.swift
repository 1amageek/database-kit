// Descriptor.swift
// Core - Unified descriptor protocol for Persistable metadata
//
// All metadata descriptors (Index, Relationship, Encryption, TTL, etc.)
// conform to this protocol, enabling modular extension of Persistable types.

/// Unified protocol for all Persistable metadata descriptors
///
/// This protocol enables a single `descriptors` array in `Persistable` to hold
/// all types of metadata, with type-safe access provided by extensions in each module.
///
/// **Design Philosophy**:
/// - Core defines only the protocol
/// - Each feature module defines its concrete Descriptor type
/// - Modules provide type-safe accessors via `Persistable` extensions
///
/// **Built-in Descriptor Types**:
/// - `IndexDescriptor`: Index metadata (Core)
///
/// **Extension Descriptor Types** (in separate modules):
/// - `RelationshipDescriptor`: FK relationship metadata (Relationship module)
/// - Future: `EncryptionDescriptor`, `TTLDescriptor`, `ValidationDescriptor`, etc.
///
/// **Usage**:
/// ```swift
/// // Define a custom Descriptor in your module
/// public struct EncryptionDescriptor: Descriptor {
///     public let name: String
///     public let propertyName: String
///     public let algorithm: EncryptionAlgorithm
/// }
///
/// // Provide type-safe accessor
/// extension Persistable {
///     static var encryptionDescriptors: [EncryptionDescriptor] {
///         descriptors.compactMap { $0 as? EncryptionDescriptor }
///     }
/// }
/// ```
public protocol Descriptor: Sendable, Hashable {
    /// Unique identifier for this descriptor
    ///
    /// For indexes: index name (e.g., "User_email")
    /// For relationships: relationship name (e.g., "Order_customer")
    var name: String { get }
}
