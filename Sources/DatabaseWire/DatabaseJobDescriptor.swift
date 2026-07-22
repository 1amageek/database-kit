/// Statically associates one job identifier with its request and response types.
public protocol DatabaseJobDescriptor {
    associatedtype Request: DatabaseWireValue
    associatedtype Response: DatabaseWireValue

    static func jobOperationIdentifier()
        throws(DatabaseWireError) -> DatabaseJobOperationIdentifier
}
