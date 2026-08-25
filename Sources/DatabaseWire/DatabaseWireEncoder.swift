import DatabaseTypes

/// The directional boundary that creates canonical DatabaseWire
/// request and response frames.
public struct DatabaseWireEncoder: Sendable {
    public static let protocolVersion: UInt16 =
        EnvelopeWireFormat.protocolVersion

    public let limits: DatabaseWireLimits

    public init(limits: DatabaseWireLimits = .default) {
        self.limits = limits
    }

    #if DATABASE_KIT_MULTI_BASE
    public func encodeRequest<Request, Response>(
        _ operation: DatabaseOperation<Request, Response>,
        requestID: UInt64,
        target: DatabaseOperationTarget,
        metadata: OperationRequestMetadata = OperationRequestMetadata(),
        request: Request
    ) throws(DatabaseWireError) -> ByteString {
        try operation.encodeRequest(
            requestID: requestID,
            target: target,
            metadata: metadata,
            request: request,
            limits: limits
        )
    }
    #else
    public func encodeRequest<Request, Response>(
        _ operation: DatabaseOperation<Request, Response>,
        requestID: UInt64,
        metadata: OperationRequestMetadata = OperationRequestMetadata(),
        request: Request
    ) throws(DatabaseWireError) -> ByteString {
        try operation.encodeRequest(
            requestID: requestID,
            metadata: metadata,
            request: request,
            limits: limits
        )
    }
    #endif

    /// Encodes only the operation request body.
    ///
    /// This is the canonical representation stored by resumable job runtimes.
    /// It excludes request identity and metadata because those belong to the
    /// outer invocation envelope.
    public func encodeRequestPayload<Request, Response>(
        _ operation: DatabaseOperation<Request, Response>,
        request: Request
    ) throws(DatabaseWireError) -> ByteString {
        try operation.encodeRequestPayload(request, limits: limits)
    }

    public func encodeResponse<Request, Response>(
        _ operation: DatabaseOperation<Request, Response>,
        requestID: UInt64,
        response: Response
    ) throws(DatabaseWireError) -> ByteString {
        try operation.encodeResponse(
            requestID: requestID,
            response: response,
            limits: limits
        )
    }

    public func encodeFailure(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        error: RemoteOperationError
    ) throws(DatabaseWireError) -> ByteString {
        try EnvelopeWireFormat.encode(
            response: DatabaseWireResponseEnvelope(
                requestID: requestID,
                operation: operation,
                payload: .failure(error)
            ),
            limits: limits
        )
    }

    /// Reattaches a previously validated successful response body to a new
    /// request envelope without decoding or copying the payload.
    ///
    /// Idempotency replay uses this operation to preserve the exact canonical
    /// response bytes committed with the original mutation.
    public func encodeSuccessPayload(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        payload: ByteString
    ) throws(DatabaseWireError) -> ByteString {
        try EnvelopeWireFormat.encodeSuccessResponse(
            requestID: requestID,
            operation: operation,
            payload: payload,
            limits: limits
        )
    }

    /// Validates an already encoded successful response body before it is
    /// persisted for idempotency replay.
    public func validateSuccessPayload(
        _ payload: borrowing ByteString
    ) throws(DatabaseWireError) {
        try EnvelopeWireFormat.validateSuccessResponsePayloadByteCount(
            payload.count,
            limits: limits
        )
    }

    public func encodeResponseAndPayload<Request, Response>(
        _ operation: DatabaseOperation<Request, Response>,
        requestID: UInt64,
        response: Response
    ) throws(DatabaseWireError) -> DatabaseWireEncodedResponse {
        try EnvelopeWireFormat.encodeSuccessResponseAndPayload(
            requestID: requestID,
            operation: operation.identifier,
            limits: limits
        ) {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) in
            try operation.encodeResponseBody(response, into: &writer)
        }
    }

    /// Measures a canonical operation response body without allocating it.
    @_spi(DatabaseExecution)
    public func responsePayloadByteCount<Request, Response>(
        _ operation: DatabaseOperation<Request, Response>,
        response: Response
    ) throws(DatabaseWireError) -> Int {
        try DatabaseWireWriter.encodedByteCount(limits: limits) {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) in
            try operation.encodeResponseBody(response, into: &writer)
        }
    }

    /// Initializes an exactly sized response-body destination in one pass.
    /// The destination pointer cannot escape this synchronous boundary.
    @_spi(DatabaseExecution)
    public func encodeResponsePayload<Request, Response>(
        _ operation: DatabaseOperation<Request, Response>,
        response: Response,
        into output: UnsafeMutableRawBufferPointer
    ) throws(DatabaseWireError) {
        try DatabaseWireWriter.encode(into: output, limits: limits) {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) in
            try operation.encodeResponseBody(response, into: &writer)
        }
    }
}
