public enum DatabaseTypedReadCommandOperation<
    Command: DatabaseReadCommandDescriptor
>: DatabaseOperation {
    public typealias Request = DatabaseTypedCommandRequest<Command>
    public typealias Response = DatabaseTypedReadCommandResponse<Command.Output>

    public static var identifier: DatabaseOperationIdentifier { .commandRead }
}
