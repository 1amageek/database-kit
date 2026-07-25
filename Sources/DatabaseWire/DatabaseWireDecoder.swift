import DatabaseTypes

/// The directional boundary that validates and decodes canonical version 1
/// DatabaseWire request and response frames.
public struct DatabaseWireDecoder: Sendable {
    public let limits: DatabaseWireLimits

    public init(limits: DatabaseWireLimits = .default) {
        self.limits = limits
    }

    public func decodeRequestEnvelope(
        _ frame: ByteString
    ) throws(DatabaseWireError) -> DatabaseWireRequestEnvelope {
        try EnvelopeWireFormat.decodeRequest(frame, limits: limits)
    }

    public func decodeRequestHeader(
        _ frame: ByteString
    ) throws(DatabaseWireError) -> DatabaseWireEnvelopeHeader {
        try EnvelopeWireFormat.decodeRequestHeader(frame)
    }

    public func decodeRequest<Request, Response>(
        _ operation: DatabaseOperation<Request, Response>,
        from frame: ByteString
    ) throws(DatabaseWireError) -> DecodedOperationRequest<Request> {
        let envelope = try decodeRequestEnvelope(frame)
        return DecodedOperationRequest(
            requestID: envelope.requestID,
            metadata: envelope.metadata,
            request: try operation.decodeRequest(
                envelope,
                limits: limits
            )
        )
    }

    public func decodeRequest<Request, Response>(
        _ operation: DatabaseOperation<Request, Response>,
        from envelope: DatabaseWireRequestEnvelope
    ) throws(DatabaseWireError) -> Request {
        try operation.decodeRequest(envelope, limits: limits)
    }

    public func decodeResponseHeader(
        _ frame: ByteString
    ) throws(DatabaseWireError) -> DatabaseWireEnvelopeHeader {
        try EnvelopeWireFormat.decodeResponseHeader(frame)
    }

    public func decodeResponse<Request, Response>(
        _ operation: DatabaseOperation<Request, Response>,
        from frame: ByteString,
        matching requestID: UInt64
    ) throws(DatabaseWireError) -> Result<Response, RemoteOperationError> {
        try operation.decodeResponse(
            frame,
            matching: requestID,
            limits: limits
        )
    }
}
