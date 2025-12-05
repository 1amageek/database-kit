// Snapshot.swift
// Core - Query result wrapper with relationship support

/// A point-in-time snapshot of a Persistable item with optional loaded relationships.
///
/// All queries return `Snapshot<T>` instead of raw `T`. This provides:
/// - Uniform API for all query results
/// - Optional relationship loading via `joining()`
/// - Type-safe access to loaded relationships via `ref()` and `refs()`
///
/// ## Basic Usage
///
/// ```swift
/// // Query without joins
/// let orders = try await context.fetch(Order.self).execute()
/// for order in orders {
///     order.id           // String (via dynamicMember)
///     order.total        // Double (via dynamicMember)
///     order.customerID   // String? (FK value, via dynamicMember)
/// }
/// ```
///
/// ## With To-One Relationship Loading
///
/// ```swift
/// // Query with to-one join
/// let orders = try await context.fetch(Order.self)
///     .joining(\.customerID)
///     .execute()
///
/// for order in orders {
///     // Access via ref() method
///     let customer = order.ref(Customer.self, \.customerID)
///     print(customer?.name)
/// }
/// ```
///
/// ## With To-Many Relationship Loading
///
/// ```swift
/// // Query with to-many join
/// let customers = try await context.fetch(Customer.self)
///     .joining(\.orderIDs)
///     .execute()
///
/// for customer in customers {
///     // Access via refs() method
///     let orders = customer.refs(Order.self, \.orderIDs)
///     for order in orders {
///         print(order.total)
///     }
/// }
/// ```
///
/// ## Accessing the Raw Item
///
/// ```swift
/// let snapshot: Snapshot<Order> = ...
/// let rawOrder: Order = snapshot.item
/// ```
@dynamicMemberLookup
public struct Snapshot<T: Persistable>: Sendable {

    // MARK: - Properties

    /// The underlying Persistable item
    public let item: T

    /// Loaded relationships keyed by FK KeyPath
    ///
    /// This is populated when using `joining()` in queries.
    /// Access via generated properties (e.g., `order.customer`) or
    /// via `ref()`/`refs()` methods.
    ///
    /// Note: `nonisolated(unsafe)` is used because AnyKeyPath is not Sendable,
    /// but this is safe since relations are only set during initialization
    /// and the `with()` methods create new Snapshot instances.
    public nonisolated(unsafe) var relations: [AnyKeyPath: any Sendable]

    // MARK: - Initialization

    /// Create a snapshot with an item and optional pre-loaded relations
    ///
    /// - Parameters:
    ///   - item: The Persistable item
    ///   - relations: Dictionary of loaded relationships keyed by FK KeyPath
    public init(item: T, relations: [AnyKeyPath: any Sendable] = [:]) {
        self.item = item
        self.relations = relations
    }

    // MARK: - Dynamic Member Lookup

    /// Access properties of the underlying item directly
    ///
    /// ```swift
    /// let order: Snapshot<Order> = ...
    /// order.total  // Same as order.item.total
    /// ```
    public subscript<V>(dynamicMember keyPath: KeyPath<T, V>) -> V {
        item[keyPath: keyPath]
    }

    // MARK: - Relationship Access

    /// Access a to-one relationship by FK KeyPath (optional FK)
    ///
    /// Returns `nil` if:
    /// - The FK value is nil
    /// - The relationship was not loaded via `joining()`
    ///
    /// ```swift
    /// let customer = order.ref(Customer.self, \.customerID)
    /// ```
    ///
    /// - Parameters:
    ///   - type: The related Persistable type
    ///   - keyPath: KeyPath to the optional FK field
    /// - Returns: The loaded related item, or nil
    public func ref<R: Persistable>(_ type: R.Type, _ keyPath: KeyPath<T, String?>) -> R? {
        relations[keyPath] as? R
    }

    /// Access a to-one relationship by FK KeyPath (required FK)
    ///
    /// Returns `nil` if the relationship was not loaded via `joining()`.
    ///
    /// ```swift
    /// let post = comment.ref(Post.self, \.postID)
    /// ```
    ///
    /// - Parameters:
    ///   - type: The related Persistable type
    ///   - keyPath: KeyPath to the required FK field
    /// - Returns: The loaded related item, or nil
    public func ref<R: Persistable>(_ type: R.Type, _ keyPath: KeyPath<T, String>) -> R? {
        relations[keyPath] as? R
    }

    /// Access a to-many relationship by FK array KeyPath
    ///
    /// Returns an empty array if the relationship was not loaded via `joining()`.
    ///
    /// ```swift
    /// let songs = playlist.refs(Song.self, \.songIDs)
    /// ```
    ///
    /// - Parameters:
    ///   - type: The related Persistable type
    ///   - keyPath: KeyPath to the FK array field
    /// - Returns: Array of loaded related items (empty if not loaded)
    public func refs<R: Persistable>(_ type: R.Type, _ keyPath: KeyPath<T, [String]>) -> [R] {
        // Note: We can't directly cast [any Persistable] to [R] because Swift arrays
        // are not covariant. We need to cast each element individually.
        guard let items = relations[keyPath] as? [any Persistable] else {
            return []
        }
        return items.compactMap { $0 as? R }
    }

    // MARK: - Mutation

    /// Create a new snapshot with an additional loaded relationship
    ///
    /// - Parameters:
    ///   - keyPath: The FK KeyPath for this relationship
    ///   - value: The loaded related item
    /// - Returns: A new Snapshot with the relationship added
    public func with<R: Persistable>(
        _ keyPath: KeyPath<T, String?>,
        loadedAs value: R?
    ) -> Snapshot<T> {
        var newRelations = relations
        if let value = value {
            newRelations[keyPath] = value
        }
        return Snapshot(item: item, relations: newRelations)
    }

    /// Create a new snapshot with an additional loaded to-many relationship
    ///
    /// - Parameters:
    ///   - keyPath: The FK array KeyPath for this relationship
    ///   - value: The loaded related items
    /// - Returns: A new Snapshot with the relationship added
    public func with<R: Persistable>(
        _ keyPath: KeyPath<T, [String]>,
        loadedAs value: [R]
    ) -> Snapshot<T> {
        var newRelations = relations
        newRelations[keyPath] = value
        return Snapshot(item: item, relations: newRelations)
    }
}

// MARK: - Equatable

extension Snapshot: Equatable where T: Equatable {
    public static func == (lhs: Snapshot<T>, rhs: Snapshot<T>) -> Bool {
        lhs.item == rhs.item
    }
}

// MARK: - Hashable

extension Snapshot: Hashable where T: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(item)
    }
}

// MARK: - Identifiable

extension Snapshot: Identifiable where T: Identifiable {
    public var id: T.ID {
        item.id
    }
}

// MARK: - CustomStringConvertible

extension Snapshot: CustomStringConvertible {
    public var description: String {
        let relCount = relations.count
        let relInfo = relCount > 0 ? ", \(relCount) relation(s) loaded" : ""
        return "Snapshot<\(T.persistableType)>(\(item.id)\(relInfo))"
    }
}

// MARK: - CustomDebugStringConvertible

extension Snapshot: CustomDebugStringConvertible {
    public var debugDescription: String {
        var parts = ["Snapshot<\(T.persistableType)>"]
        parts.append("  item: \(item)")
        if !relations.isEmpty {
            parts.append("  relations:")
            for (keyPath, value) in relations {
                parts.append("    \(keyPath): \(value)")
            }
        }
        return parts.joined(separator: "\n")
    }
}
