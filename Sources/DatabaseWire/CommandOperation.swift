public enum CommandOperation<
    Command: CommandDescriptor
>: DatabaseOperation {
    public typealias Request = CommandInvocation<Command>
    public typealias Response = Command.Result

    public static var identifier: DatabaseOperationIdentifier {
        .commandExecute
    }
}
