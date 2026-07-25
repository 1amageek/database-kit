import DatabaseTypes

/// A resumable job whose request and completed response are bound to one
/// closed database operation descriptor.
public struct JobOperation<
    Request: Sendable,
    Response: Sendable
>: Sendable {
    public let identifier: JobOperationIdentifier
    public let operation: DatabaseOperation<Request, Response>

    init(
        identifier: JobOperationIdentifier,
        operation: DatabaseOperation<Request, Response>
    ) {
        self.identifier = identifier
        self.operation = operation
    }

    public func makeStartRequest(
        _ request: Request,
        maximumSliceWorkUnits: UInt64 = 100_000,
        retryPolicy: JobStartOperation.RetryPolicy = .init(),
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> JobStartOperation.Request {
        JobStartOperation.Request(
            operation: identifier,
            requestPayload: try operation.encodeRequestPayload(
                request,
                limits: limits
            ),
            maximumSliceWorkUnits: maximumSliceWorkUnits,
            retryPolicy: retryPolicy
        )
    }

    public func decodeCompletedResponse(
        _ payload: ByteString,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> Response {
        try operation.decodeResponsePayload(payload, limits: limits)
    }
}

public extension DatabaseOperation {
    func resumableJob(
        kind: String
    ) throws(DatabaseWireError) -> JobOperation<Request, Response> {
        JobOperation(
            identifier: try JobOperationIdentifier(
                family: identifier,
                kind: kind
            ),
            operation: self
        )
    }
}

public enum JobOperations {
    public static let maintenance: JobOperation<
        MaintenanceExecuteOperation.Request,
        MaintenanceExecuteOperation.Response
    > = JobOperation(
        identifier: JobOperationIdentifier(
            validatedFamily: .maintenanceExecute,
            validatedKind: "database.maintenance"
        ),
        operation: DatabaseOperations.maintenanceExecute
    )
}
