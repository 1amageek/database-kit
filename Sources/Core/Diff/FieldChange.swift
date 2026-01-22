// FieldChange.swift
// Core - Field-level change representation
//
// Represents a single field change in a model diff.

import Foundation

// MARK: - ChangeType

/// Type of change detected for a field
///
/// Used to categorize changes in a diff result.
public enum ChangeType: String, Sendable, Codable, Hashable {
    /// Field value was not changed
    case unchanged

    /// Field was added (old value was null)
    case added

    /// Field was removed (new value is null)
    case removed

    /// Field value was modified
    case modified
}

// MARK: - FieldChange

/// Represents a single field change between two model instances
///
/// **Design**: Uses `FieldValue` for type-safe comparison and serialization.
/// Field paths use dot notation for nested fields (e.g., "address.city").
///
/// **Usage**:
/// ```swift
/// let change = FieldChange(
///     fieldPath: "email",
///     oldValue: .string("old@example.com"),
///     newValue: .string("new@example.com")
/// )
/// print(change.changeType)  // .modified
/// ```
///
/// **Nested Fields**:
/// ```swift
/// let change = FieldChange(
///     fieldPath: "address.city",
///     oldValue: .string("Tokyo"),
///     newValue: .string("Osaka")
/// )
/// ```
public struct FieldChange: Sendable, Hashable, Codable {

    // MARK: - Properties

    /// Dot-notation field path (e.g., "address.city")
    public let fieldPath: String

    /// Value before the change (`.null` if field was added)
    public let oldValue: FieldValue

    /// Value after the change (`.null` if field was removed)
    public let newValue: FieldValue

    /// Override for changeType when custom comparator determines equality
    ///
    /// When a custom comparator is used and determines the values are equal,
    /// this is set to `.unchanged` to ensure `changeType` reflects the
    /// custom comparison result rather than the default FieldValue equality.
    private let changeTypeOverride: ChangeType?

    // MARK: - Initialization

    /// Create a field change
    ///
    /// - Parameters:
    ///   - fieldPath: Dot-notation path to the field
    ///   - oldValue: Value before the change
    ///   - newValue: Value after the change
    public init(fieldPath: String, oldValue: FieldValue, newValue: FieldValue) {
        self.fieldPath = fieldPath
        self.oldValue = oldValue
        self.newValue = newValue
        self.changeTypeOverride = nil
    }

    /// Create a field change with explicit change type override
    ///
    /// Used when custom comparators determine equality differently than
    /// the default FieldValue comparison.
    ///
    /// - Parameters:
    ///   - fieldPath: Dot-notation path to the field
    ///   - oldValue: Value before the change
    ///   - newValue: Value after the change
    ///   - changeTypeOverride: Override for the computed changeType
    public init(
        fieldPath: String,
        oldValue: FieldValue,
        newValue: FieldValue,
        changeTypeOverride: ChangeType?
    ) {
        self.fieldPath = fieldPath
        self.oldValue = oldValue
        self.newValue = newValue
        self.changeTypeOverride = changeTypeOverride
    }

    // MARK: - Computed Properties

    /// Type of change (computed from old/new values, or overridden by custom comparator)
    ///
    /// If `changeTypeOverride` is set (e.g., from a custom comparator), returns that value.
    /// Otherwise computes based on old/new values:
    /// - `.unchanged`: Both values are equal
    /// - `.added`: Old value is null, new value is not
    /// - `.removed`: Old value is not null, new value is null
    /// - `.modified`: Both values are non-null and different
    public var changeType: ChangeType {
        if let override = changeTypeOverride {
            return override
        }
        switch (oldValue.isNull, newValue.isNull) {
        case (true, true):
            return .unchanged
        case (true, false):
            return .added
        case (false, true):
            return .removed
        case (false, false):
            return oldValue == newValue ? .unchanged : .modified
        }
    }

    /// Whether this represents an actual change
    public var isChanged: Bool {
        changeType != .unchanged
    }

    /// The root field name (without nested path)
    ///
    /// For "address.city", returns "address"
    public var rootFieldName: String {
        if let dotIndex = fieldPath.firstIndex(of: ".") {
            return String(fieldPath[..<dotIndex])
        }
        return fieldPath
    }

    /// Whether this is a nested field change
    public var isNestedField: Bool {
        fieldPath.contains(".")
    }

    /// Nested path components
    ///
    /// For "address.city", returns ["address", "city"]
    public var pathComponents: [String] {
        fieldPath.split(separator: ".").map(String.init)
    }
}

// MARK: - CustomStringConvertible

extension FieldChange: CustomStringConvertible {
    public var description: String {
        switch changeType {
        case .unchanged:
            return "\(fieldPath): unchanged"
        case .added:
            return "\(fieldPath): added \(newValue)"
        case .removed:
            return "\(fieldPath): removed \(oldValue)"
        case .modified:
            return "\(fieldPath): \(oldValue) -> \(newValue)"
        }
    }
}

// MARK: - CustomDebugStringConvertible

extension FieldChange: CustomDebugStringConvertible {
    public var debugDescription: String {
        "FieldChange(path: \"\(fieldPath)\", type: \(changeType), old: \(oldValue), new: \(newValue))"
    }
}
