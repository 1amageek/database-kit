import DatabaseTypes
/// DirectoryPathError - Errors related to directory path resolution

public enum DirectoryPathError: Error, CustomStringConvertible, Sendable {
    /// Required fields are missing
    case missingFields([String])

    /// Type has dynamic directory but field values not provided
    case dynamicFieldsRequired(typeName: String, fields: [String])

    /// A dynamic directory field does not match its compiled schema.
    case invalidField(typeName: String, field: String, reason: String)

    public var description: String {
        switch self {
        case .missingFields(let fields):
            return "Missing directory field values: \(fields.joined(separator: ", ")). " +
                   "Use .partition() to specify values for all Field components."

        case .dynamicFieldsRequired(let typeName, let fields):
            return "Type '\(typeName)' requires field values for directory resolution: " +
                   "\(fields.joined(separator: ", ")). " +
                   "Use .partition(\\.\(fields.first ?? "field"), equals: value)."

        case .invalidField(let typeName, let field, let reason):
            return "Directory field '\(field)' on type '\(typeName)' is invalid: \(reason)"
        }
    }
}
