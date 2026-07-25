/// The transaction access required by an application command.
public enum CommandAccess: UInt8, Sendable, Hashable {
    case readOnly = 0
    case readWrite = 1
}
