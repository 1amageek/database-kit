import DatabaseTypes

/// The directional boundary that creates canonical version 1 DatabaseWire
/// request and response frames.
public struct DatabaseWireEncoder: Sendable {
    public static let protocolVersion: UInt16 =
        EnvelopeWireFormat.protocolVersion

    public let limits: DatabaseWireLimits

    public init(limits: DatabaseWireLimits = .default) {
        self.limits = limits
    }

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
}
