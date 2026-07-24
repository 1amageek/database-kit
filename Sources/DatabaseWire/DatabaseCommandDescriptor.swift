import DatabaseTypes
public protocol DatabaseCommandDescriptor: Sendable {
    associatedtype Input: DatabaseWireValue
    associatedtype Output: DatabaseWireValue

    static var identifier: String { get }
    static var access: DatabaseCommandAccess { get }
}
