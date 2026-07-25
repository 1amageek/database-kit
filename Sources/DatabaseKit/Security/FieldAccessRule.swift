import DatabaseTypes

/// Static read and write authorization for one persisted field.
public struct FieldAccessRule: Sendable, Hashable {
    public let field: FieldIdentity
    public let read: FieldAccessLevel
    public let write: FieldAccessLevel

    public init(
        field: FieldIdentity,
        read: FieldAccessLevel,
        write: FieldAccessLevel
    ) {
        self.field = field
        self.read = read
        self.write = write
    }
}
