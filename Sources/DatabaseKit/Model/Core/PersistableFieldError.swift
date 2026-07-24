import DatabaseTypes
public enum PersistableFieldError: Error, Sendable, Equatable {
    case invalidNumber(UInt32)
    case emptyName
}
