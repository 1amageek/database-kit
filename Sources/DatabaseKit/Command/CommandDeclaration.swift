/// The semantic declaration of one application-defined database command.
public struct CommandDeclaration: Sendable, Hashable {
    public let identifier: CommandIdentifier
    public let access: CommandAccess

    public init(
        identifier: CommandIdentifier,
        access: CommandAccess
    ) {
        self.identifier = identifier
        self.access = access
    }
}
