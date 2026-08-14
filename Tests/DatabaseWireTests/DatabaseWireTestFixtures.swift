import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire

func makeTestDatabaseRequestEnvelope(
    requestID: UInt64,
    operation: DatabaseOperationIdentifier,
    metadata: OperationRequestMetadata = OperationRequestMetadata(),
    payload: ByteString
) -> DatabaseWireRequestEnvelope {
    #if DATABASE_KIT_MULTIPLE_BASES
    DatabaseWireRequestEnvelope(
        requestID: requestID,
        operation: operation,
        target: .database,
        metadata: metadata,
        payload: payload
    )
    #else
    DatabaseWireRequestEnvelope(
        requestID: requestID,
        operation: operation,
        metadata: metadata,
        payload: payload
    )
    #endif
}

extension DatabaseWireEncoder {
    func encodeTestDatabaseRequest<Request, Response>(
        _ operation: DatabaseOperation<Request, Response>,
        requestID: UInt64,
        metadata: OperationRequestMetadata = OperationRequestMetadata(),
        request: Request
    ) throws(DatabaseWireError) -> ByteString {
        #if DATABASE_KIT_MULTIPLE_BASES
        try encodeRequest(
            operation,
            requestID: requestID,
            target: .database,
            metadata: metadata,
            request: request
        )
        #else
        try encodeRequest(
            operation,
            requestID: requestID,
            metadata: metadata,
            request: request
        )
        #endif
    }
}

extension DatabaseOperation {
    func encodeTestDatabaseRequest(
        requestID: UInt64,
        metadata: OperationRequestMetadata = OperationRequestMetadata(),
        request: Request,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        #if DATABASE_KIT_MULTIPLE_BASES
        try encodeRequest(
            requestID: requestID,
            target: .database,
            metadata: metadata,
            request: request,
            limits: limits
        )
        #else
        try encodeRequest(
            requestID: requestID,
            metadata: metadata,
            request: request,
            limits: limits
        )
        #endif
    }
}

func makeTestJobIdentity(
    jobID: DatabaseTypes.UUID,
    operation: JobOperationIdentifier
) -> JobIdentity {
    #if DATABASE_KIT_MULTIPLE_BASES
    JobIdentity(jobID: jobID, operation: operation, target: .database)
    #else
    JobIdentity(jobID: jobID, operation: operation)
    #endif
}

func makeTestJobStartRequest(
    operation: JobOperationIdentifier,
    requestPayload: ByteString,
    maximumSliceWorkUnits: UInt64 = 100_000,
    retryPolicy: JobStartOperation.RetryPolicy = .init()
) -> JobStartOperation.Request {
    #if DATABASE_KIT_MULTIPLE_BASES
    JobStartOperation.Request(
        target: .database,
        operation: operation,
        requestPayload: requestPayload,
        maximumSliceWorkUnits: maximumSliceWorkUnits,
        retryPolicy: retryPolicy
    )
    #else
    JobStartOperation.Request(
        operation: operation,
        requestPayload: requestPayload,
        maximumSliceWorkUnits: maximumSliceWorkUnits,
        retryPolicy: retryPolicy
    )
    #endif
}

func makeTestJobStartResponse(
    jobID: DatabaseTypes.UUID,
    operation: JobOperationIdentifier
) -> JobStartOperation.Response {
    #if DATABASE_KIT_MULTIPLE_BASES
    JobStartOperation.Response(
        jobID: jobID,
        operation: operation,
        target: .database
    )
    #else
    JobStartOperation.Response(jobID: jobID, operation: operation)
    #endif
}

func makeTestJobResultDigestAccumulator(
    operation: JobOperationIdentifier
) -> JobResultDigestAccumulator {
    #if DATABASE_KIT_MULTIPLE_BASES
    JobResultDigestAccumulator(operation: operation, target: .database)
    #else
    JobResultDigestAccumulator(operation: operation)
    #endif
}

func makeTestJobOperationStartRequest<Request, Response>(
    _ operation: JobOperation<Request, Response>,
    request: Request,
    maximumSliceWorkUnits: UInt64 = 100_000,
    retryPolicy: JobStartOperation.RetryPolicy = .init(),
    limits: DatabaseWireLimits = .default
) throws(DatabaseWireError) -> JobStartOperation.Request {
    #if DATABASE_KIT_MULTIPLE_BASES
    try operation.makeStartRequest(
        request,
        target: .database,
        maximumSliceWorkUnits: maximumSliceWorkUnits,
        retryPolicy: retryPolicy,
        limits: limits
    )
    #else
    try operation.makeStartRequest(
        request,
        maximumSliceWorkUnits: maximumSliceWorkUnits,
        retryPolicy: retryPolicy,
        limits: limits
    )
    #endif
}

#if DATABASE_KIT_MULTIPLE_BASES
func makeTestReadConsistency(
    version: UInt64 = 1
) throws -> DatabaseReadConsistency {
    .transactional(
        try DomainReadPoint(
            domainID: "primary",
            position: .version(version)
        )
    )
}
#endif

func makeTestQueryRowPage(
    columns: [QueryColumn],
    rows: [QueryRow],
    continuation: ByteString? = nil,
    snapshotVersion: UInt64? = nil
) throws -> QueryRowPage {
    #if DATABASE_KIT_MULTIPLE_BASES
    try QueryRowPage(
        columns: columns,
        rows: rows,
        continuation: continuation,
        provenance: nil,
        consistency: try makeTestReadConsistency(
            version: snapshotVersion ?? 1
        )
    )
    #else
    try QueryRowPage(
        columns: columns,
        rows: rows,
        continuation: continuation,
        snapshotVersion: snapshotVersion
    )
    #endif
}

func makeTestRDFGraphPage(
    quads: consuming [RDFQuad],
    continuation: ByteString? = nil,
    snapshotVersion: Int64? = nil
) throws -> RDFGraphPage {
    #if DATABASE_KIT_MULTIPLE_BASES
    return try RDFGraphPage(
        quads: quads,
        continuation: continuation,
        provenance: nil,
        consistency: try makeTestReadConsistency(
            version: UInt64(snapshotVersion ?? 1)
        )
    )
    #else
    return RDFGraphPage(
        quads: quads,
        continuation: continuation,
        snapshotVersion: snapshotVersion
    )
    #endif
}

func makeTestBooleanResponse(
    _ value: Bool,
    snapshotVersion: UInt64 = 1
) throws -> QueryExecuteOperation.Response {
    #if DATABASE_KIT_MULTIPLE_BASES
    .boolean(
        try QueryBooleanResult(
            value: value,
            provenance: nil,
            consistency: try makeTestReadConsistency(
                version: snapshotVersion
            )
        )
    )
    #else
    .boolean(value)
    #endif
}

func testBooleanValue(
    _ value: QueryExecuteOperation.Response
) -> Bool? {
    guard case .boolean(let boolean) = value else {
        return nil
    }
    #if DATABASE_KIT_MULTIPLE_BASES
    return boolean.value
    #else
    return boolean
    #endif
}
