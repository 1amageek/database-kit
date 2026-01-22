// DiffOptions.swift
// Core - Diff computation options
//
// Configures how diffs are computed between model instances.

import Foundation

// MARK: - DiffOptions

/// Options for controlling diff computation
///
/// **Design**: Provides fine-grained control over diff behavior including
/// array comparison mode, field exclusion, and custom comparators.
///
/// **Basic Usage**:
/// ```swift
/// // Default options (suitable for most cases)
/// let diff = newUser.diff(from: oldUser)
///
/// // With custom options
/// var options = DiffOptions()
/// options.excludeFields = ["updatedAt", "lastLoginAt"]
/// let diff = try ModelDiffBuilder.diff(old: oldUser, new: newUser, options: options)
/// ```
///
/// **Array Diff Options**:
/// ```swift
/// var options = DiffOptions()
/// options.detailedArrayDiff = true  // Element-level diff
/// options.maxArrayDiffSize = 500    // OOM prevention
/// ```
///
/// **Custom Comparators**:
/// ```swift
/// var options = DiffOptions()
/// options.customComparators["timestamp"] = { old, new in
///     // Custom equality check (e.g., ignore sub-second precision)
///     guard let oldDouble = old.asDouble, let newDouble = new.asDouble else { return false }
///     return abs(oldDouble - newDouble) < 1.0
/// }
/// ```
public struct DiffOptions: Sendable {

    // MARK: - Array Diff Options

    /// Enable element-level array diff
    ///
    /// When `false` (default), arrays are compared as a whole:
    /// - Any difference results in a single change with the entire array
    ///
    /// When `true`, arrays are compared element by element:
    /// - Each changed element gets its own `FieldChange`
    /// - Field paths use index notation: "tags.0", "tags.1", etc.
    ///
    /// **Performance**: Element-level diff is O(n) and can be expensive for large arrays.
    /// Use `maxArrayDiffSize` to prevent OOM issues.
    public var detailedArrayDiff: Bool

    /// Maximum array size for element-level diff
    ///
    /// Arrays larger than this limit will fall back to whole-array comparison
    /// even if `detailedArrayDiff` is enabled. This prevents OOM issues.
    ///
    /// Default: 1000 elements
    public var maxArrayDiffSize: Int

    // MARK: - Field Filtering

    /// Fields to exclude from diff computation
    ///
    /// Field paths in this set will be skipped entirely.
    /// Supports dot notation for nested fields.
    ///
    /// **Common Use Cases**:
    /// - Exclude auto-updated timestamps: `["updatedAt", "modifiedAt"]`
    /// - Exclude computed fields: `["fullName"]`
    /// - Exclude sensitive fields: `["passwordHash"]`
    public var excludeFields: Set<String>

    /// Include unchanged fields in the diff result
    ///
    /// When `false` (default), only actually changed fields are included.
    /// When `true`, all fields appear in the diff with their change type.
    ///
    /// **Use Cases**:
    /// - Audit logging that needs complete field snapshots
    /// - Debugging diff behavior
    public var includeUnchanged: Bool

    // MARK: - Custom Comparators

    /// Custom equality comparators for specific fields
    ///
    /// Allows overriding the default `FieldValue` equality check for specific fields.
    /// The comparator should return `true` if values are considered equal.
    ///
    /// **Example**: Ignore sub-second timestamp differences
    /// ```swift
    /// options.customComparators["timestamp"] = { old, new in
    ///     guard let o = old.asDouble, let n = new.asDouble else { return old == new }
    ///     return abs(o - n) < 1.0  // Within 1 second
    /// }
    /// ```
    ///
    /// **Note**: Key is the field path (supports dot notation)
    public var customComparators: [String: @Sendable (FieldValue, FieldValue) -> Bool]

    // MARK: - Initialization

    /// Create diff options with defaults
    ///
    /// Default values:
    /// - `detailedArrayDiff`: false
    /// - `maxArrayDiffSize`: 1000
    /// - `excludeFields`: empty
    /// - `includeUnchanged`: false
    /// - `customComparators`: empty
    public init(
        detailedArrayDiff: Bool = false,
        maxArrayDiffSize: Int = 1000,
        excludeFields: Set<String> = [],
        includeUnchanged: Bool = false,
        customComparators: [String: @Sendable (FieldValue, FieldValue) -> Bool] = [:]
    ) {
        self.detailedArrayDiff = detailedArrayDiff
        self.maxArrayDiffSize = maxArrayDiffSize
        self.excludeFields = excludeFields
        self.includeUnchanged = includeUnchanged
        self.customComparators = customComparators
    }

    // MARK: - Presets

    /// Default options (whole-array comparison, no exclusions)
    public static let `default` = DiffOptions()

    /// Options for audit logging (includes unchanged fields)
    public static let audit = DiffOptions(includeUnchanged: true)

    /// Options for detailed debugging (element-level arrays, includes unchanged)
    public static let debug = DiffOptions(
        detailedArrayDiff: true,
        includeUnchanged: true
    )

    // MARK: - Builder Methods

    /// Create a copy with detailed array diff enabled
    public func withDetailedArrayDiff(_ enabled: Bool = true) -> DiffOptions {
        var copy = self
        copy.detailedArrayDiff = enabled
        return copy
    }

    /// Create a copy with additional excluded fields
    public func excluding(_ fields: String...) -> DiffOptions {
        var copy = self
        copy.excludeFields = excludeFields.union(fields)
        return copy
    }

    /// Create a copy with unchanged fields included
    public func includingUnchanged(_ include: Bool = true) -> DiffOptions {
        var copy = self
        copy.includeUnchanged = include
        return copy
    }

    /// Create a copy with a custom comparator added
    public func withComparator(
        for field: String,
        _ comparator: @escaping @Sendable (FieldValue, FieldValue) -> Bool
    ) -> DiffOptions {
        var copy = self
        copy.customComparators[field] = comparator
        return copy
    }
}

// MARK: - Codable (Partial)

extension DiffOptions: Codable {
    enum CodingKeys: String, CodingKey {
        case detailedArrayDiff
        case maxArrayDiffSize
        case excludeFields
        case includeUnchanged
        // Note: customComparators cannot be encoded (closures)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.detailedArrayDiff = try container.decodeIfPresent(Bool.self, forKey: .detailedArrayDiff) ?? false
        self.maxArrayDiffSize = try container.decodeIfPresent(Int.self, forKey: .maxArrayDiffSize) ?? 1000
        self.excludeFields = try container.decodeIfPresent(Set<String>.self, forKey: .excludeFields) ?? []
        self.includeUnchanged = try container.decodeIfPresent(Bool.self, forKey: .includeUnchanged) ?? false
        self.customComparators = [:]  // Cannot decode closures
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(detailedArrayDiff, forKey: .detailedArrayDiff)
        try container.encode(maxArrayDiffSize, forKey: .maxArrayDiffSize)
        try container.encode(excludeFields, forKey: .excludeFields)
        try container.encode(includeUnchanged, forKey: .includeUnchanged)
        // Note: customComparators are not encoded
    }
}

// MARK: - CustomStringConvertible

extension DiffOptions: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []

        if detailedArrayDiff {
            parts.append("detailedArrayDiff(max: \(maxArrayDiffSize))")
        }
        if !excludeFields.isEmpty {
            parts.append("exclude: [\(excludeFields.sorted().joined(separator: ", "))]")
        }
        if includeUnchanged {
            parts.append("includeUnchanged")
        }
        if !customComparators.isEmpty {
            parts.append("customComparators: [\(customComparators.keys.sorted().joined(separator: ", "))]")
        }

        if parts.isEmpty {
            return "DiffOptions.default"
        }
        return "DiffOptions(\(parts.joined(separator: ", ")))"
    }
}
