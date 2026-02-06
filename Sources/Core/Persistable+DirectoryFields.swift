/// Persistable+DirectoryFields - Directory field name extraction

extension Persistable {
    /// Get field names for directory Field components
    public static var directoryFieldNames: [String] {
        directoryPathComponents.compactMap { component -> String? in
            guard let dynamicElement = component as? any DynamicDirectoryElement else { return nil }
            return fieldName(for: dynamicElement.anyKeyPath)
        }
    }

    /// Returns true if directoryPathComponents contains any dynamic Field element
    public static var hasDynamicDirectory: Bool {
        directoryPathComponents.contains { $0 is any DynamicDirectoryElement }
    }
}
