import DatabaseTypes

/// A closed, statically typed database operation descriptor.
///
/// DatabaseWire constructs the exported descriptors. Applications select one
/// of those descriptors and cannot replace its identifier or binary
/// representation.
public struct DatabaseOperation<
    Request: Sendable,
    Response: Sendable
>: Sendable {
    public let identifier: DatabaseOperationIdentifier

    private let encodeRequestBody:
        @Sendable (
            Request,
            inout DatabaseWireWriter
        ) throws(DatabaseWireError) -> Void
    private let decodeRequestBody:
        @Sendable (
            inout DatabaseWireReader
        ) throws(DatabaseWireError) -> Request
    private let encodeResponseBody:
        @Sendable (
            Response,
            inout DatabaseWireWriter
        ) throws(DatabaseWireError) -> Void
    private let decodeResponseBody:
        @Sendable (
            inout DatabaseWireReader
        ) throws(DatabaseWireError) -> Response

    init(
        identifier: DatabaseOperationIdentifier,
        encodeRequest:
            @escaping @Sendable (
                Request,
                inout DatabaseWireWriter
            ) throws(DatabaseWireError) -> Void,
        decodeRequest:
            @escaping @Sendable (
                inout DatabaseWireReader
            ) throws(DatabaseWireError) -> Request,
        encodeResponse:
            @escaping @Sendable (
                Response,
                inout DatabaseWireWriter
            ) throws(DatabaseWireError) -> Void,
        decodeResponse:
            @escaping @Sendable (
                inout DatabaseWireReader
            ) throws(DatabaseWireError) -> Response
    ) {
        self.identifier = identifier
        self.encodeRequestBody = encodeRequest
        self.decodeRequestBody = decodeRequest
        self.encodeResponseBody = encodeResponse
        self.decodeResponseBody = decodeResponse
    }

    func encodeRequestPayload(
        _ request: Request,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try EnvelopeWireFormat.encodeValue(
            request,
            limits: limits,
            encode: encodeRequestBody
        )
    }

    func decodeRequestPayload(
        _ payload: ByteString,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> Request {
        try EnvelopeWireFormat.decodeValue(
            from: payload,
            limits: limits,
            decode: decodeRequestBody
        )
    }

    func encodeResponsePayload(
        _ response: Response,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try EnvelopeWireFormat.encodeValue(
            response,
            limits: limits,
            encode: encodeResponseBody
        )
    }

    func encodeResponseBody(
        _ response: Response,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeResponseBody(response, &writer)
    }

    func decodeResponsePayload(
        _ payload: ByteString,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> Response {
        try EnvelopeWireFormat.decodeValue(
            from: payload,
            limits: limits,
            decode: decodeResponseBody
        )
    }

    #if DATABASE_KIT_MULTIPLE_BASES
    func encodeRequest(
        requestID: UInt64,
        target: DatabaseOperationTarget,
        metadata: OperationRequestMetadata = OperationRequestMetadata(),
        request: Request,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try EnvelopeWireFormat.encodeRequest(
            identifier: identifier,
            requestID: requestID,
            target: target,
            metadata: metadata,
            request: request,
            limits: limits,
            encode: encodeRequestBody
        )
    }
    #else
    func encodeRequest(
        requestID: UInt64,
        metadata: OperationRequestMetadata = OperationRequestMetadata(),
        request: Request,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try EnvelopeWireFormat.encodeRequest(
            identifier: identifier,
            requestID: requestID,
            metadata: metadata,
            request: request,
            limits: limits,
            encode: encodeRequestBody
        )
    }
    #endif

    func decodeRequest(
        _ envelope: DatabaseWireRequestEnvelope,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> Request {
        guard envelope.operation == identifier else {
            throw .unexpectedOperationIdentifier(
                expected: identifier,
                actual: envelope.operation
            )
        }
        return try decodeRequestPayload(envelope.payload, limits: limits)
    }

    func encodeResponse(
        requestID: UInt64,
        response: Response,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try EnvelopeWireFormat.encodeSuccessResponse(
            requestID: requestID,
            operation: identifier,
            limits: limits
        ) {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) in
            try encodeResponseBody(response, &writer)
        }
    }

    func decodeResponse(
        _ frame: ByteString,
        matching requestID: UInt64,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> Result<Response, RemoteOperationError> {
        let envelope = try EnvelopeWireFormat.decodeResponse(
            frame,
            limits: limits
        )
        guard envelope.requestID == requestID else {
            throw .unexpectedRequestIdentifier(
                expected: requestID,
                actual: envelope.requestID
            )
        }
        guard envelope.operation == identifier else {
            throw .unexpectedOperationIdentifier(
                expected: identifier,
                actual: envelope.operation
            )
        }
        switch envelope.payload {
        case .success(let payload):
            return .success(
                try decodeResponsePayload(payload, limits: limits)
            )
        case .failure(let error):
            return .failure(error)
        }
    }
}

protocol DatabaseOperationDeclaration: Sendable {
    associatedtype Request: WireValue
    associatedtype Response: WireValue

    static var identifier: DatabaseOperationIdentifier { get }
}
