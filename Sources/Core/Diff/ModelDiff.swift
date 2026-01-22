// ModelDiff.swift
// Core - Model diff result
//
// Represents the complete diff result between two model instances.

import Foundation

// MARK: - VersionInfo

/// Version information for diff context
///
/// Used to track which versions are being compared in a diff.
public struct VersionInfo: Sendable, Codable, Hashable {

    /// Version identifier (e.g., versionstamp string)
    public let versionID: String

    /// Timestamp when this version was created (optional)
    public let timestamp: Date?

    /// Create version info
    ///
    /// - Parameters:
    ///   - versionID: Version identifier string
    ///   - timestamp: Optional timestamp for this version
    public init(versionID: String, timestamp: Date? = nil) {
        self.versionID = versionID
        self.timestamp = timestamp
    }
}

// MARK: - ModelDiff

/// Represents the diff result between two model instances
///
/// **Design**: Collects all field changes with metadata about the comparison.
/// Supports version tracking for integration with VersionIndex.
///
/// **Usage**:
/// ```swift
/// let diff = newUser.diff(from: oldUser)
///
/// // Check if there are any changes
/// if !diff.isEmpty {
///     print("Modified fields: \(diff.modifiedFields)")
///     print("Total changes: \(diff.changeCount)")
/// }
///
/// // Get specific field change
/// if let emailChange = diff.change(for: "email") {
///     print("Email changed from \(emailChange.oldValue) to \(emailChange.newValue)")
/// }
/// ```
///
/// **With Version History**:
/// ```swift
/// let diff = try await context.versions(Document.self)
///     .forItem(docId)
///     .diff(from: version1, to: version2)
///
/// print("From version: \(diff.oldVersion?.versionID ?? "unknown")")
/// print("To version: \(diff.newVersion?.versionID ?? "unknown")")
/// ```
public struct ModelDiff: Sendable, Codable {

    // MARK: - Properties

    /// Type name of the compared models
    public let typeName: String

    /// ID of the model (string representation)
    public let idString: String

    /// All field changes detected
    public let changes: [FieldChange]

    /// Timestamp when the diff was computed
    public let timestamp: Date?

    /// Version info for the older model (optional)
    public let oldVersion: VersionInfo?

    /// Version info for the newer model (optional)
    public let newVersion: VersionInfo?

    // MARK: - Initialization

    /// Create a model diff
    ///
    /// - Parameters:
    ///   - typeName: Type name of the models being compared
    ///   - idString: ID of the model (string representation)
    ///   - changes: Array of field changes
    ///   - timestamp: When the diff was computed (defaults to now)
    ///   - oldVersion: Version info for older model (optional)
    ///   - newVersion: Version info for newer model (optional)
    public init(
        typeName: String,
        idString: String,
        changes: [FieldChange],
        timestamp: Date? = Date(),
        oldVersion: VersionInfo? = nil,
        newVersion: VersionInfo? = nil
    ) {
        self.typeName = typeName
        self.idString = idString
        self.changes = changes
        self.timestamp = timestamp
        self.oldVersion = oldVersion
        self.newVersion = newVersion
    }

    // MARK: - Computed Properties

    /// Whether there are no changes
    public var isEmpty: Bool {
        changes.allSatisfy { $0.changeType == .unchanged }
    }

    /// Number of actual changes (excludes unchanged fields)
    public var changeCount: Int {
        changes.filter { $0.changeType != .unchanged }.count
    }

    /// Field paths that were modified
    public var modifiedFields: [String] {
        changes(ofType: .modified).map(\.fieldPath)
    }

    /// Field paths that were added
    public var addedFields: [String] {
        changes(ofType: .added).map(\.fieldPath)
    }

    /// Field paths that were removed
    public var removedFields: [String] {
        changes(ofType: .removed).map(\.fieldPath)
    }

    /// All field paths with actual changes
    public var changedFields: [String] {
        changes.filter { $0.isChanged }.map(\.fieldPath)
    }

    /// Whether version information is available
    public var hasVersionInfo: Bool {
        oldVersion != nil || newVersion != nil
    }

    // MARK: - Query Methods

    /// Get changes of a specific type
    ///
    /// - Parameter type: The change type to filter by
    /// - Returns: Array of field changes matching the type
    public func changes(ofType type: ChangeType) -> [FieldChange] {
        changes.filter { $0.changeType == type }
    }

    /// Get the change for a specific field path
    ///
    /// - Parameter fieldPath: The field path to look up
    /// - Returns: The field change if found, nil otherwise
    public func change(for fieldPath: String) -> FieldChange? {
        changes.first { $0.fieldPath == fieldPath }
    }

    /// Check if a specific field was changed
    ///
    /// - Parameter fieldPath: The field path to check
    /// - Returns: True if the field has a non-unchanged entry
    public func hasChange(for fieldPath: String) -> Bool {
        guard let change = change(for: fieldPath) else { return false }
        return change.isChanged
    }

    /// Get all changes for fields under a specific root path
    ///
    /// Useful for getting all nested changes under a parent field.
    ///
    /// - Parameter rootPath: The root path prefix (e.g., "address")
    /// - Returns: Array of field changes whose path starts with the root
    public func changes(under rootPath: String) -> [FieldChange] {
        let prefix = rootPath + "."
        return changes.filter { $0.fieldPath == rootPath || $0.fieldPath.hasPrefix(prefix) }
    }

    // MARK: - Transformation Methods

    /// Create a new diff with only actual changes (excluding unchanged fields)
    public func compacted() -> ModelDiff {
        ModelDiff(
            typeName: typeName,
            idString: idString,
            changes: changes.filter { $0.isChanged },
            timestamp: timestamp,
            oldVersion: oldVersion,
            newVersion: newVersion
        )
    }

    /// Create a new diff with version info added
    ///
    /// - Parameters:
    ///   - oldVersion: Version info for older model
    ///   - newVersion: Version info for newer model
    /// - Returns: New diff with version info
    public func withVersions(old: VersionInfo?, new: VersionInfo?) -> ModelDiff {
        ModelDiff(
            typeName: typeName,
            idString: idString,
            changes: changes,
            timestamp: timestamp,
            oldVersion: old,
            newVersion: new
        )
    }
}

// MARK: - CustomStringConvertible

extension ModelDiff: CustomStringConvertible {
    public var description: String {
        if isEmpty {
            return "ModelDiff(\(typeName)#\(idString)): no changes"
        }

        var parts = ["ModelDiff(\(typeName)#\(idString)): \(changeCount) changes"]

        if !modifiedFields.isEmpty {
            parts.append("  modified: \(modifiedFields.joined(separator: ", "))")
        }
        if !addedFields.isEmpty {
            parts.append("  added: \(addedFields.joined(separator: ", "))")
        }
        if !removedFields.isEmpty {
            parts.append("  removed: \(removedFields.joined(separator: ", "))")
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - CustomDebugStringConvertible

extension ModelDiff: CustomDebugStringConvertible {
    public var debugDescription: String {
        var result = "ModelDiff(type: \"\(typeName)\", id: \"\(idString)\""

        if let oldVersion = oldVersion {
            result += ", oldVersion: \"\(oldVersion.versionID)\""
        }
        if let newVersion = newVersion {
            result += ", newVersion: \"\(newVersion.versionID)\""
        }

        result += ", changes: ["
        result += changes.map(\.debugDescription).joined(separator: ", ")
        result += "])"

        return result
    }
}

// MARK: - Hashable

extension ModelDiff: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(typeName)
        hasher.combine(idString)
        hasher.combine(changes)
    }

    public static func == (lhs: ModelDiff, rhs: ModelDiff) -> Bool {
        lhs.typeName == rhs.typeName &&
        lhs.idString == rhs.idString &&
        lhs.changes == rhs.changes
    }
}
