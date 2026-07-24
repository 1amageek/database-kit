import DatabaseTypes
public protocol DatabaseOperation: Sendable {
    associatedtype Request: DatabaseWireValue
    associatedtype Response: DatabaseWireValue

    static var identifier: DatabaseOperationIdentifier { get }
}
