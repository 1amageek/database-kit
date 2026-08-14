/// The complete operation catalog for the selected runtime feature set.
public enum DatabaseOperationCatalog {
    public static let capabilitiesDescribe = operation(
        CapabilitiesDescribeOperation.self
    )
    public static let schemaDescribe = operation(
        SchemaDescribeOperation.self
    )
    public static let schemaExecute = operation(
        SchemaExecuteOperation.self
    )
    #if DATABASE_KIT_MULTIPLE_BASES
    public static let baseExecute = operation(
        BaseExecuteOperation.self
    )
    public static let compositionExecute = operation(
        CompositionExecuteOperation.self
    )
    public static let grantExecute = operation(
        GrantExecuteOperation.self
    )
    #endif
    public static let queryExecute = operation(
        QueryExecuteOperation.self
    )
    public static let mutationExecute = operation(
        MutationExecuteOperation.self
    )
    public static let graphAlgorithm = operation(
        GraphAlgorithmOperation.self
    )
    public static let ontologyExecute = operation(
        OntologyExecuteOperation.self
    )
    public static let shaclExecute = operation(
        SHACLExecuteOperation.self
    )
    public static let commandExecute = operation(
        CommandExecuteOperation.self
    )
    public static let maintenanceExecute = operation(
        MaintenanceExecuteOperation.self
    )
    public static let jobStart = operation(
        JobStartOperation.self
    )
    public static let jobStatus = operation(
        JobStatusOperation.self
    )
    public static let jobResult = operation(
        JobResultOperation.self
    )
    public static let jobCancel = operation(
        JobCancelOperation.self
    )

    private static func operation<Declaration>(
        _ declaration: Declaration.Type
    ) -> DatabaseOperation<
        Declaration.Request,
        Declaration.Response
    > where Declaration: DatabaseOperationDeclaration {
        DatabaseOperation(
            identifier: Declaration.identifier,
            encodeRequest: {
                (
                    request: Declaration.Request,
                    writer: inout DatabaseWireWriter
                ) throws(DatabaseWireError) in
                try request.encode(into: &writer)
            },
            decodeRequest: {
                (reader: inout DatabaseWireReader)
                    throws(DatabaseWireError) in
                try Declaration.Request(from: &reader)
            },
            encodeResponse: {
                (
                    response: Declaration.Response,
                    writer: inout DatabaseWireWriter
                ) throws(DatabaseWireError) in
                try response.encode(into: &writer)
            },
            decodeResponse: {
                (reader: inout DatabaseWireReader)
                    throws(DatabaseWireError) in
                try Declaration.Response(from: &reader)
            }
        )
    }
}
