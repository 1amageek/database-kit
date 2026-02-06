/// DirectoryPathError - Errors related to directory path resolution

public enum DirectoryPathError: Error, CustomStringConvertible, Sendable {
    /// Required fields are missing
    case missingFields([String])

    /// Type has dynamic directory but field values not provided
    case dynamicFieldsRequired(typeName: String, fields: [String])

    public var description: String {
        switch self {
        case .missingFields(let fields):
            return "Missing directory field values: \(fields.joined(separator: ", ")). " +
                   "Use .partition() to specify values for all Field components."

        case .dynamicFieldsRequired(let typeName, let fields):
            return "Type '\(typeName)' requires field values for directory resolution: " +
                   "\(fields.joined(separator: ", ")). " +
                   "Use .partition(\\.\(fields.first ?? "field"), equals: value)."
        }
    }
}
