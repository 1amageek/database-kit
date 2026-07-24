public protocol CommandDescriptor: Sendable {
    associatedtype Input: DatabaseWireValue
    associatedtype Output: DatabaseWireValue
    associatedtype Result: CommandResult where Result.Output == Output

    static var identifier: String { get }
    static var access: CommandAccess { get }
}
