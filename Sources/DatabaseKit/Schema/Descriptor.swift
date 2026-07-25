import DatabaseTypes
// Descriptor.swift
// Core - Common identity contract for schema declarations
//
// Feature-specific declarations remain in homogeneous collections. This
// protocol only defines their shared stable identity.

/// Common stable identity for a schema declaration.
///
/// Persistable metadata is deliberately not exposed as `[any Descriptor]`.
/// Indexes, relationships, and ontology bindings have different invariants and
/// consumers, so each remains in its own typed collection. That separation
/// preserves static dispatch and Embedded compatibility.
public protocol Descriptor: Sendable, Hashable {
    /// Unique identifier for this descriptor
    ///
    /// For indexes: index name (e.g., "User_email")
    /// For relationships: relationship name (e.g., "Order_customer")
    var name: String { get }
}
