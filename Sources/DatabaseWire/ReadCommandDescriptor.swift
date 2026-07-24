public protocol ReadCommandDescriptor: CommandDescriptor
where Result == ReadCommandResult<Output> {}

extension ReadCommandDescriptor {
    public static var access: CommandAccess { .readOnly }
}
