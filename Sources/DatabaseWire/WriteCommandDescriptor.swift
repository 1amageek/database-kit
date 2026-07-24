public protocol WriteCommandDescriptor: CommandDescriptor
where Result == WriteCommandResult<Output> {}

extension WriteCommandDescriptor {
    public static var access: CommandAccess { .readWrite }
}
