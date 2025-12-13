// Restricted.swift
// Core - Property wrapper for field-level access control

import Foundation

/// Protocol to identify Restricted property wrappers at runtime
public protocol RestrictedProtocol: Sendable {
    /// Read access level
    var readAccess: FieldAccessLevel { get }

    /// Write access level
    var writeAccess: FieldAccessLevel { get }

    /// The underlying value as Any
    var anyValue: Any { get }

    /// The value type
    static var valueType: Any.Type { get }
}

/// Property wrapper for field-level access control
///
/// Restricts read and/or write access to a field based on authentication context.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Employee {
///     var id: String = ULID().ulidString
///     var name: String = ""
///
///     // Only HR and managers can read/write salary
///     @Restricted(read: .roles(["hr", "manager"]), write: .roles(["hr"]))
///     var salary: Double = 0
///
///     // Only HR can read SSN
///     @Restricted(read: .roles(["hr"]))
///     var ssn: String = ""
///
///     // Anyone can read, but only admin can write
///     @Restricted(write: .roles(["admin"]))
///     var department: String = ""
///
///     // Only authenticated users can read
///     @Restricted(read: .authenticated)
///     var internalNotes: String = ""
/// }
/// ```
///
/// **Evaluation**:
/// - Use `FDBContext.fetchSecure()` to automatically mask restricted fields
/// - Use `FDBContext.saveSecure()` to validate write permissions
@propertyWrapper
public struct Restricted<Value: Sendable>: Sendable, RestrictedProtocol {
    private var value: Value

    /// Read access level
    public let readAccess: FieldAccessLevel

    /// Write access level
    public let writeAccess: FieldAccessLevel

    /// The wrapped value
    public var wrappedValue: Value {
        get { value }
        set { value = newValue }
    }

    /// The projected value (provides access to the wrapper itself)
    public var projectedValue: Restricted<Value> {
        get { self }
        set { self = newValue }
    }

    /// Initialize with access levels
    ///
    /// - Parameters:
    ///   - wrappedValue: Initial value
    ///   - read: Read access level (default: .public)
    ///   - write: Write access level (default: .public)
    public init(
        wrappedValue: Value,
        read: FieldAccessLevel = .public,
        write: FieldAccessLevel = .public
    ) {
        self.value = wrappedValue
        self.readAccess = read
        self.writeAccess = write
    }

    // MARK: - RestrictedProtocol

    public var anyValue: Any { value }

    public static var valueType: Any.Type { Value.self }
}

// MARK: - Equatable

extension Restricted: Equatable where Value: Equatable {
    public static func == (lhs: Restricted<Value>, rhs: Restricted<Value>) -> Bool {
        lhs.value == rhs.value &&
        lhs.readAccess == rhs.readAccess &&
        lhs.writeAccess == rhs.writeAccess
    }
}

// MARK: - Hashable

extension Restricted: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

// MARK: - Codable

extension Restricted: Codable where Value: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(Value.self)
        // Access levels are not encoded - they come from the type definition
        self.readAccess = .public
        self.writeAccess = .public
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - CustomStringConvertible

extension Restricted: CustomStringConvertible where Value: CustomStringConvertible {
    public var description: String {
        "Restricted(\(value.description), read: \(readAccess), write: \(writeAccess))"
    }
}
