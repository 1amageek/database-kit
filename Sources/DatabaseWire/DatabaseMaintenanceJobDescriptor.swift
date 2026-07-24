import DatabaseTypes
/// Typed descriptor for resumable database maintenance jobs.
public enum DatabaseMaintenanceJobDescriptor: DatabaseJobDescriptor {
    public typealias Request = MaintenanceExecuteOperation.Request
    public typealias Response = MaintenanceExecuteOperation.Response

    public static func jobOperationIdentifier()
        throws(DatabaseWireError) -> DatabaseJobOperationIdentifier {
        try DatabaseJobOperationIdentifier(
            family: .maintenanceExecute,
            kind: "database.maintenance"
        )
    }
}
