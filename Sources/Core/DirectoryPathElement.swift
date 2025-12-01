// DirectoryPathElement.swift
// Core - Type-safe directory path components for #Directory macro

import Foundation

// MARK: - DirectoryPathElement Protocol

/// Protocol for directory path elements
///
/// Directory paths can contain string literals and KeyPath references.
/// This protocol allows type-safe specification of heterogeneous path elements.
///
/// **Usage**:
/// ```swift
/// #Directory<Order>(
///     "tenants",           // String literal → Path
///     Field(\.accountID),  // KeyPath wrapper → Field
///     "orders",
///     layer: .partition
/// )
/// ```
///
/// **Conforming Types**:
/// - `Path`: Static string literal path component
/// - `Field<Root>`: Dynamic KeyPath-based path component for partitioning
public protocol DirectoryPathElement: Sendable {
    associatedtype Value
    var value: Value { get }
}

// MARK: - Path (Static String Component)

/// Static string literal path element
///
/// Represents a fixed path component in the directory hierarchy.
/// Automatically created from string literals via `ExpressibleByStringLiteral`.
///
/// **Example**:
/// ```swift
/// #Directory<User>("app", "users")
/// // Expands to: [Path("app"), Path("users")]
/// ```
public struct Path: DirectoryPathElement, ExpressibleByStringLiteral, Hashable, Sendable {
    public let value: String

    public init(stringLiteral value: String) {
        self.value = value
    }

    public init(_ value: String) {
        self.value = value
    }
}

// MARK: - Field (Dynamic KeyPath Component)

/// KeyPath-based path element for dynamic partitioning
///
/// Wraps a KeyPath to a field in the record type, used for multi-tenant directories.
/// The actual value is resolved at runtime from the record instance.
///
/// **Usage**:
/// ```swift
/// #Directory<Order>(
///     "tenants",
///     Field(\.tenantID),  // Dynamic: resolved from record.tenantID
///     "orders",
///     layer: .partition
/// )
///
/// // When creating a store:
/// let store = try await Order.store(tenantID: "acme", ...)
/// // Resolves to directory: tenants/acme/orders
/// ```
///
/// **Multi-level Partitioning**:
/// ```swift
/// #Directory<Message>(
///     "tenants", Field(\.tenantID),
///     "channels", Field(\.channelID),
///     "messages",
///     layer: .partition
/// )
/// ```
public struct Field<Root>: DirectoryPathElement, @unchecked Sendable {
    public let value: PartialKeyPath<Root>

    public init(_ keyPath: PartialKeyPath<Root>) {
        self.value = keyPath
    }
}

// MARK: - String Extension

extension String: DirectoryPathElement {
    public var value: String { self }
}
