/// A typed request together with the correlation and execution metadata from
/// its canonical DatabaseWire envelope.
public struct DecodedOperationRequest<Request: Sendable>: Sendable {
    public let requestID: UInt64
    public let metadata: OperationRequestMetadata
    public let request: Request

    init(
        requestID: UInt64,
        metadata: OperationRequestMetadata,
        request: Request
    ) {
        self.requestID = requestID
        self.metadata = metadata
        self.request = request
    }
}
