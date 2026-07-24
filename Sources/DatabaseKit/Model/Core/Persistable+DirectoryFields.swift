import DatabaseTypes
/// Persistable+DirectoryFields - Directory field name extraction

extension Persistable {
    /// Get field names for directory Field components
    public static var directoryFieldNames: [String] {
        directoryPathComponents.compactMap { component in
            guard case .dynamicField(let fieldName) = component else { return nil }
            return fieldName
        }
    }

    /// Returns true if directoryPathComponents contains any dynamic Field element
    public static var hasDynamicDirectory: Bool {
        directoryPathComponents.contains {
            if case .dynamicField = $0 { return true }
            return false
        }
    }
}
