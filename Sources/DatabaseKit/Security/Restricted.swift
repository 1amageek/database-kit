import DatabaseTypes
// Restricted.swift
// Core - Property wrapper for field-level access control


/// Property wrapper for field-level access control
///
/// Declares read and write authorization for a persisted field.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Employee {
///     var id: String
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
/// `@Persistable` compiles the arguments into a static `FieldAccessRule`. The
/// wrapper stores only the field value; authorization rules are not duplicated
/// in every model instance.
@propertyWrapper
public struct Restricted<Value: Sendable>: Sendable {
    private var value: Value

    /// The wrapped value
    public var wrappedValue: Value {
        get { value }
        set { value = newValue }
    }

    /// Initialize with access levels
    ///
    /// - Parameters:
    ///   - wrappedValue: Initial value
    ///   - read: Read access level (default: .public)
    ///   - write: Write access level (default: .public)
    public init(
        wrappedValue: Value,
        read _: FieldAccessLevel = .public,
        write _: FieldAccessLevel = .public
    ) {
        self.value = wrappedValue
    }

}

// MARK: - Equatable

extension Restricted: Equatable where Value: Equatable {
    public static func == (lhs: Restricted<Value>, rhs: Restricted<Value>) -> Bool {
        lhs.value == rhs.value
    }
}

// MARK: - Hashable

extension Restricted: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

// MARK: - CustomStringConvertible

extension Restricted: CustomStringConvertible where Value: CustomStringConvertible {
    public var description: String {
        value.description
    }
}
