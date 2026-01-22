// DiffError.swift
// Core - Diff computation errors
//
// Errors that can occur during diff computation.

import Foundation

// MARK: - DiffError

/// Errors that can occur during diff computation
///
/// **Common Scenarios**:
/// - Version-based diff when model not found at specified version
/// - Field extraction failures for complex types
/// - Type conversion issues
public enum DiffError: Error, Sendable {

    /// Model not found at the specified version
    ///
    /// Occurs when attempting to diff against a historical version
    /// that doesn't exist in the version history.
    ///
    /// - Parameters:
    ///   - id: The model ID that was being looked up
    ///   - version: The version that was not found
    case modelNotFoundAtVersion(id: String, version: String)

    /// Field not found in the model
    ///
    /// Occurs when attempting to access a field that doesn't exist
    /// or is not accessible via the Persistable interface.
    ///
    /// - Parameters:
    ///   - fieldPath: The field path that was not found
    ///   - typeName: The type name where the field was expected
    case fieldNotFound(fieldPath: String, typeName: String)

    /// Failed to convert field value to FieldValue
    ///
    /// Occurs when a field's value cannot be represented as a FieldValue.
    /// This typically happens with custom types that don't have a
    /// FieldValue representation.
    ///
    /// - Parameters:
    ///   - fieldPath: The field path with the conversion issue
    ///   - valueType: The actual type of the value
    case conversionFailed(fieldPath: String, valueType: String)

    /// Type mismatch between compared models
    ///
    /// Occurs when attempting to diff models of different types.
    /// This shouldn't happen with properly typed code but can occur
    /// with type-erased operations.
    ///
    /// - Parameters:
    ///   - expected: The expected type name
    ///   - actual: The actual type name
    case typeMismatch(expected: String, actual: String)

    /// Invalid field path format
    ///
    /// Occurs when a field path has an invalid format
    /// (e.g., empty string, consecutive dots).
    ///
    /// - Parameter fieldPath: The invalid field path
    case invalidFieldPath(fieldPath: String)

    /// Version history not available
    ///
    /// Occurs when attempting version-based diff but the model
    /// doesn't have version history enabled.
    ///
    /// - Parameter typeName: The type that doesn't have version history
    case versionHistoryNotAvailable(typeName: String)

    /// Insufficient version history
    ///
    /// Occurs when there aren't enough versions to compute a diff
    /// (e.g., only one version exists when trying to get previous diff).
    ///
    /// - Parameters:
    ///   - id: The model ID
    ///   - required: Number of versions required
    ///   - available: Number of versions available
    case insufficientVersionHistory(id: String, required: Int, available: Int)
}

// MARK: - CustomStringConvertible

extension DiffError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .modelNotFoundAtVersion(let id, let version):
            return "Model '\(id)' not found at version '\(version)'"

        case .fieldNotFound(let fieldPath, let typeName):
            return "Field '\(fieldPath)' not found in type '\(typeName)'"

        case .conversionFailed(let fieldPath, let valueType):
            return "Failed to convert field '\(fieldPath)' of type '\(valueType)' to FieldValue"

        case .typeMismatch(let expected, let actual):
            return "Type mismatch: expected '\(expected)', got '\(actual)'"

        case .invalidFieldPath(let fieldPath):
            return "Invalid field path: '\(fieldPath)'"

        case .versionHistoryNotAvailable(let typeName):
            return "Version history not available for type '\(typeName)'"

        case .insufficientVersionHistory(let id, let required, let available):
            return "Insufficient version history for '\(id)': requires \(required) versions, only \(available) available"
        }
    }
}

// MARK: - LocalizedError

extension DiffError: LocalizedError {
    public var errorDescription: String? {
        description
    }

    public var failureReason: String? {
        switch self {
        case .modelNotFoundAtVersion:
            return "The specified version does not exist in the version history"
        case .fieldNotFound:
            return "The field does not exist or is not accessible"
        case .conversionFailed:
            return "The field value type is not supported for diff comparison"
        case .typeMismatch:
            return "Cannot compare models of different types"
        case .invalidFieldPath:
            return "The field path format is invalid"
        case .versionHistoryNotAvailable:
            return "The model type does not have version tracking enabled"
        case .insufficientVersionHistory:
            return "Not enough versions exist to perform the requested diff"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .modelNotFoundAtVersion:
            return "Verify the version identifier and ensure the model was saved at that version"
        case .fieldNotFound:
            return "Check that the field name is correct and included in allFields"
        case .conversionFailed:
            return "Ensure the field type conforms to FieldValueConvertible or can be converted to a supported type"
        case .typeMismatch:
            return "Ensure both models are of the same type before comparing"
        case .invalidFieldPath:
            return "Use valid field paths (e.g., 'name' or 'address.city')"
        case .versionHistoryNotAvailable:
            return "Add VersionIndexKind to the model's index descriptors"
        case .insufficientVersionHistory:
            return "Wait for more versions to be saved or use a different comparison method"
        }
    }
}

// MARK: - Equatable

extension DiffError: Equatable {
    public static func == (lhs: DiffError, rhs: DiffError) -> Bool {
        switch (lhs, rhs) {
        case (.modelNotFoundAtVersion(let lid, let lv), .modelNotFoundAtVersion(let rid, let rv)):
            return lid == rid && lv == rv
        case (.fieldNotFound(let lp, let lt), .fieldNotFound(let rp, let rt)):
            return lp == rp && lt == rt
        case (.conversionFailed(let lp, let lt), .conversionFailed(let rp, let rt)):
            return lp == rp && lt == rt
        case (.typeMismatch(let le, let la), .typeMismatch(let re, let ra)):
            return le == re && la == ra
        case (.invalidFieldPath(let l), .invalidFieldPath(let r)):
            return l == r
        case (.versionHistoryNotAvailable(let l), .versionHistoryNotAvailable(let r)):
            return l == r
        case (.insufficientVersionHistory(let lid, let lr, let la), .insufficientVersionHistory(let rid, let rr, let ra)):
            return lid == rid && lr == rr && la == ra
        default:
            return false
        }
    }
}
