// Persistable+Diff.swift
// Core - Persistable extension for diff computation
//
// Provides basic diff functionality using Persistable's allFields and dynamicMember.

import Foundation

// MARK: - Persistable+Diff

extension Persistable {

    /// Compute diff from another instance of the same type
    ///
    /// This is a simple diff implementation that:
    /// - Uses `allFields` to iterate over all fields
    /// - Uses `dynamicMember` subscript to access field values
    /// - Converts values to `FieldValue` for comparison
    ///
    /// **Limitations**:
    /// - Does not support nested field diffing (use `ModelDiffBuilder` in DatabaseEngine)
    /// - Does not support custom comparators (use `DiffOptions` with `ModelDiffBuilder`)
    /// - Array comparison is whole-array only
    ///
    /// **Usage**:
    /// ```swift
    /// var newUser = oldUser
    /// newUser.email = "new@example.com"
    ///
    /// let diff = newUser.diff(from: oldUser)
    /// print(diff.modifiedFields)  // ["email"]
    /// ```
    ///
    /// - Parameter other: The older model to compare against (base)
    /// - Returns: ModelDiff containing all field changes
    public func diff(from other: Self) -> ModelDiff {
        var changes: [FieldChange] = []

        for fieldName in Self.allFields {
            let oldValue = convertToFieldValue(other[dynamicMember: fieldName])
            let newValue = convertToFieldValue(self[dynamicMember: fieldName])

            if oldValue != newValue {
                changes.append(FieldChange(
                    fieldPath: fieldName,
                    oldValue: oldValue,
                    newValue: newValue
                ))
            }
        }

        return ModelDiff(
            typeName: Self.persistableType,
            idString: "\(self.id)",
            changes: changes,
            timestamp: Date(),
            oldVersion: nil,
            newVersion: nil
        )
    }

    /// Compute diff from another instance with options
    ///
    /// Supports basic options from `DiffOptions`:
    /// - `excludeFields`: Skip specified field paths
    /// - `includeUnchanged`: Include fields that didn't change
    ///
    /// **Note**: Advanced options like `detailedArrayDiff` and `customComparators`
    /// require `ModelDiffBuilder` from DatabaseEngine module.
    ///
    /// - Parameters:
    ///   - other: The older model to compare against (base)
    ///   - options: Diff options
    /// - Returns: ModelDiff containing field changes
    public func diff(from other: Self, options: DiffOptions) -> ModelDiff {
        var changes: [FieldChange] = []

        for fieldName in Self.allFields {
            // Check if field should be excluded
            if options.excludeFields.contains(fieldName) {
                continue
            }

            let oldValue = convertToFieldValue(other[dynamicMember: fieldName])
            let newValue = convertToFieldValue(self[dynamicMember: fieldName])

            // Include if changed, or if includeUnchanged is enabled
            if oldValue != newValue || options.includeUnchanged {
                changes.append(FieldChange(
                    fieldPath: fieldName,
                    oldValue: oldValue,
                    newValue: newValue
                ))
            }
        }

        return ModelDiff(
            typeName: Self.persistableType,
            idString: "\(self.id)",
            changes: changes,
            timestamp: Date(),
            oldVersion: nil,
            newVersion: nil
        )
    }

    /// Check if this instance has any changes from another
    ///
    /// More efficient than computing full diff when you only need to know
    /// whether changes exist.
    ///
    /// - Parameter other: The model to compare against
    /// - Returns: True if any field differs
    public func hasChanges(from other: Self) -> Bool {
        for fieldName in Self.allFields {
            let oldValue = convertToFieldValue(other[dynamicMember: fieldName])
            let newValue = convertToFieldValue(self[dynamicMember: fieldName])

            if oldValue != newValue {
                return true
            }
        }
        return false
    }

    /// Get the list of changed field names compared to another instance
    ///
    /// - Parameter other: The model to compare against
    /// - Returns: Array of field names that differ
    public func changedFields(from other: Self) -> [String] {
        var changed: [String] = []

        for fieldName in Self.allFields {
            let oldValue = convertToFieldValue(other[dynamicMember: fieldName])
            let newValue = convertToFieldValue(self[dynamicMember: fieldName])

            if oldValue != newValue {
                changed.append(fieldName)
            }
        }

        return changed
    }
}

// MARK: - Private Helpers

private extension Persistable {

    /// Convert any Sendable value to FieldValue
    ///
    /// Attempts conversion in this order:
    /// 1. Try FieldValue.init(_:) for standard types
    /// 2. Try FieldValueConvertible protocol
    /// 3. Convert arrays recursively
    /// 4. Fall back to string description
    func convertToFieldValue(_ value: (any Sendable)?) -> FieldValue {
        guard let value = value else {
            return .null
        }

        // Try direct FieldValue conversion
        if let fieldValue = FieldValue(value) {
            return fieldValue
        }

        // Try FieldValueConvertible
        if let convertible = value as? any FieldValueConvertible {
            return convertible.toFieldValue()
        }

        // Handle arrays
        if let array = value as? [any Sendable] {
            let elements = array.map { convertToFieldValue($0) }
            return .array(elements)
        }

        // Handle Optional
        if let optional = value as? OptionalProtocol {
            if optional.isNil {
                return .null
            }
            if let unwrapped = optional.wrappedAny {
                return convertAnyToFieldValue(unwrapped)
            }
        }

        // Fall back to string description
        return .string(String(describing: value))
    }

    /// Convert Any value to FieldValue (for Optional unwrapping)
    func convertAnyToFieldValue(_ value: Any) -> FieldValue {
        // Try FieldValue conversion
        if let fieldValue = FieldValue(value) {
            return fieldValue
        }

        // Handle nested Optional
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let child = mirror.children.first {
                return convertAnyToFieldValue(child.value)
            }
            return .null
        }

        // Fall back to string
        return .string(String(describing: value))
    }
}

// MARK: - OptionalProtocol

/// Protocol to detect and unwrap Optional values at runtime
private protocol OptionalProtocol {
    var isNil: Bool { get }
    var wrappedAny: Any? { get }
}

extension Optional: OptionalProtocol {
    var isNil: Bool {
        self == nil
    }

    var wrappedAny: Any? {
        switch self {
        case .some(let value):
            return value
        case .none:
            return nil
        }
    }
}
