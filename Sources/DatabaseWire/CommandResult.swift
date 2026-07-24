import DatabaseTypes

public protocol CommandResult: DatabaseWireValue {
    associatedtype Output: DatabaseWireValue

    static var access: CommandAccess { get }

    var output: Output { get }
    var continuation: ByteString? { get }
}
