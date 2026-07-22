public enum DatabaseTypedWriteCommandOperation<
    Command: DatabaseWriteCommandDescriptor
>: DatabaseOperation {
    public typealias Request = DatabaseTypedCommandRequest<Command>
    public typealias Response = DatabaseTypedWriteCommandResponse<Command.Output>

    public static var identifier: DatabaseOperationIdentifier { .commandWrite }
}
