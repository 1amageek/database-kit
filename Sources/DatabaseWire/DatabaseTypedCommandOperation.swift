import DatabaseTypes

public enum DatabaseTypedCommandOperation<
    Command: DatabaseCommandDescriptor
>: DatabaseOperation {
    public typealias Request = DatabaseTypedCommandRequest<Command>
    public typealias Response = DatabaseTypedCommandResponse<Command>

    public static var identifier: DatabaseOperationIdentifier {
        .commandExecute
    }
}
