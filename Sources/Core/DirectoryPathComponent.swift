/// A compiled component of a database directory path.
///
/// Persistable macros emit this value model directly so runtime directory
/// resolution never depends on existential casts or key-path metadata.
public enum DirectoryPathComponent: Sendable, Codable, Equatable, Hashable {
    case staticPath(String)
    case dynamicField(fieldName: String)
}

extension DirectoryPathComponent: CustomStringConvertible {
    public var description: String {
        switch self {
        case .staticPath(let value):
            return value
        case .dynamicField(let fieldName):
            return "{\(fieldName)}"
        }
    }
}
