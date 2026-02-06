/// DirectoryComponentCatalog - Codable representation of a DirectoryPath component
///
/// Captures both static path segments and dynamic field references,
/// enabling CLI tools to understand and resolve multi-tenant directory structures.

public enum DirectoryComponentCatalog: Sendable, Codable, Equatable, Hashable {
    /// Static path segment (e.g., "app", "data")
    case staticPath(String)
    /// Dynamic field reference requiring runtime partition value (e.g., "tenantId")
    case dynamicField(fieldName: String)
}
