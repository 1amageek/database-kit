import DatabaseTypes

public struct DatabaseEncodedSuccessResponse: Sendable {
    public let frame: ByteString
    public let payload: ByteString

    public init(frame: ByteString, payload: ByteString) {
        self.frame = frame
        self.payload = payload
    }
}

public enum DatabaseEnvelopeCodec {
    public static let protocolVersion: UInt16 = 1
    private static let magic: [UInt8] = [0x44, 0x42, 0x57, 0x52]
    private static let envelopeHeaderByteCount = 17
    private static let successResponseFixedByteCount = 22

    public static func encode(
        request: DatabaseWireRequestEnvelope,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try encodeMeasured(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writeHeader(kind: .request, into: &writer)
            writer.writeUInt64(request.requestID)
            request.operation.encode(into: &writer)
            try request.metadata.encode(into: &writer)
            try writer.writeBytes(request.payload)
        }
    }

    public static func encodeRequest<Operation: DatabaseOperation>(
        _ operation: Operation.Type = Operation.self,
        requestID: UInt64,
        metadata: DatabaseRequestMetadata,
        request: Operation.Request,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try encodeMeasured(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writeHeader(kind: .request, into: &writer)
            writer.writeUInt64(requestID)
            Operation.identifier.encode(into: &writer)
            try metadata.encode(into: &writer)
            try writer.writeLengthPrefixed {
                (payloadWriter: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try request.encode(into: &payloadWriter)
            }
        }
    }

    public static func decodeRequest(
        _ bytes: ByteString,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> DatabaseWireRequestEnvelope {
        var reader = DatabaseWireReader(bytes, limits: limits)
        try validateHeader(kind: .request, reader: &reader)
        let envelope = DatabaseWireRequestEnvelope(
            requestID: try reader.readUInt64(),
            operation: try DatabaseOperationIdentifier(from: &reader),
            metadata: try DatabaseRequestMetadata(from: &reader),
            payload: try reader.readBytes()
        )
        try reader.ensureFullyRead()
        return envelope
    }

    /// Decodes only the fixed routing header without traversing metadata or payload.
    public static func decodeRequestHeader(
        _ bytes: ByteString
    ) throws(DatabaseWireError) -> DatabaseWireEnvelopeHeader {
        try decodeHeader(kind: .request, from: bytes)
    }

    public static func encode(
        response: DatabaseWireResponseEnvelope,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try encodeMeasured(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writeHeader(kind: .response, into: &writer)
            writer.writeUInt64(response.requestID)
            response.operation.encode(into: &writer)
            try response.payload.encode(into: &writer)
        }
    }

    public static func encodeSuccessResponse(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        limits: DatabaseWireLimits = .default,
        encodePayload: (inout DatabaseWireWriter) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireError) -> ByteString {
        try encodeSuccessResponseAndPayload(
            requestID: requestID,
            operation: operation,
            limits: limits,
            encodePayload: encodePayload
        ).frame
    }

    public static func encodeSuccessResponseAndPayload(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        limits: DatabaseWireLimits = .default,
        encodePayload: (inout DatabaseWireWriter) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireError) -> DatabaseEncodedSuccessResponse {
        let frame = try encodeMeasured(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writeHeader(kind: .response, into: &writer)
            writer.writeUInt64(requestID)
            operation.encode(into: &writer)
            writer.writeUInt8(1)
            try writer.writeLengthPrefixed(encodePayload)
        }
        guard frame.count >= successResponseFixedByteCount else {
            throw .byteCountOverflow
        }
        return DatabaseEncodedSuccessResponse(
            frame: frame,
            payload: frame[successResponseFixedByteCount..<frame.count]
        )
    }

    public static func encodeSuccessResponse(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        payload: ByteString,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try validateSuccessResponsePayloadByteCount(
            payload.count,
            limits: limits
        )
        return try encodeMeasured(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writeHeader(kind: .response, into: &writer)
            writer.writeUInt64(requestID)
            operation.encode(into: &writer)
            writer.writeUInt8(1)
            try writer.writeLengthPrefixed { payloadWriter in
                payloadWriter.writeUnframedBytes(payload)
            }
        }
    }

    public static func validateSuccessResponsePayloadByteCount(
        _ payloadByteCount: Int,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) {
        guard payloadByteCount >= 0 else {
            throw .byteCountOverflow
        }
        guard payloadByteCount <= limits.maximumByteStringBytes else {
            throw .byteStringTooLarge(
                actual: payloadByteCount,
                maximum: limits.maximumByteStringBytes
            )
        }
        let (frameByteCount, overflow) = successResponseFixedByteCount
            .addingReportingOverflow(payloadByteCount)
        guard !overflow else {
            throw .byteCountOverflow
        }
        guard frameByteCount <= limits.maximumFrameBytes else {
            throw .frameTooLarge(
                actual: frameByteCount,
                maximum: limits.maximumFrameBytes
            )
        }
    }

    public static func decodeResponse(
        _ bytes: ByteString,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> DatabaseWireResponseEnvelope {
        var reader = DatabaseWireReader(bytes, limits: limits)
        try validateHeader(kind: .response, reader: &reader)
        let envelope = DatabaseWireResponseEnvelope(
            requestID: try reader.readUInt64(),
            operation: try DatabaseOperationIdentifier(from: &reader),
            payload: try DatabaseWireResponsePayload(from: &reader)
        )
        try reader.ensureFullyRead()
        return envelope
    }

    /// Decodes only the fixed routing header without traversing the response payload.
    public static func decodeResponseHeader(
        _ bytes: ByteString
    ) throws(DatabaseWireError) -> DatabaseWireEnvelopeHeader {
        try decodeHeader(kind: .response, from: bytes)
    }

    public static func encode<Value: DatabaseWireValue>(
        _ value: Value,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try encodeMeasured(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try value.encode(into: &writer)
        }
    }

    public static func decode<Value: DatabaseWireValue>(
        _ type: Value.Type,
        from bytes: ByteString,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> Value {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let value = try Value(from: &reader)
        try reader.ensureFullyRead()
        return value
    }

    public static func decodeResult<Value: DatabaseWireValue>(
        _ type: Value.Type,
        from bytes: ByteString,
        limits: DatabaseWireLimits = .default
    ) -> Result<Value, DatabaseWireError> {
        do {
            return .success(
                try decode(type, from: bytes, limits: limits)
            )
        } catch {
            return .failure(error)
        }
    }

    private static func writeHeader(
        kind: DatabaseWireMessageKind,
        into writer: inout DatabaseWireWriter
    ) {
        for byte in magic { writer.writeUInt8(byte) }
        writer.writeUInt16(protocolVersion)
        writer.writeUInt8(kind.rawValue)
    }

    private static func validateHeader(
        kind: DatabaseWireMessageKind,
        reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        for byte in magic {
            guard try reader.readUInt8() == byte else { throw .invalidMagic }
        }
        let version = try reader.readUInt16()
        guard version == protocolVersion else {
            throw .unsupportedProtocolVersionValue(version)
        }
        guard try DatabaseWireMessageKind(from: &reader) == kind else {
            throw .invalidMessageKind(kind.rawValue)
        }
    }

    private static func decodeHeader(
        kind: DatabaseWireMessageKind,
        from bytes: ByteString
    ) throws(DatabaseWireError) -> DatabaseWireEnvelopeHeader {
        let readableByteCount = min(bytes.count, envelopeHeaderByteCount)
        var reader = DatabaseWireReader(bytes[0..<readableByteCount])
        try validateHeader(kind: kind, reader: &reader)
        let header = DatabaseWireEnvelopeHeader(
            requestID: try reader.readUInt64(),
            operation: try DatabaseOperationIdentifier(from: &reader)
        )
        try reader.ensureFullyRead()
        return header
    }

    private static func encodeMeasured(
        limits: DatabaseWireLimits,
        _ encode: (inout DatabaseWireWriter) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits, encode)
    }
}
