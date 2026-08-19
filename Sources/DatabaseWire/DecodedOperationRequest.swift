/// A typed request together with the correlation and execution metadata from
/// its canonical DatabaseWire envelope.
public struct DecodedOperationRequest<Request: Sendable>: Sendable {
    public let requestID: UInt64
    #if DATABASE_KIT_MULTI_BASE
    public let target: DatabaseOperationTarget
    #endif
    public let metadata: OperationRequestMetadata
    public let request: Request

    #if DATABASE_KIT_MULTI_BASE
    init(
        requestID: UInt64,
        target: DatabaseOperationTarget,
        metadata: OperationRequestMetadata,
        request: Request
    ) {
        self.requestID = requestID
        self.target = target
        self.metadata = metadata
        self.request = request
    }
    #else
    init(
        requestID: UInt64,
        metadata: OperationRequestMetadata,
        request: Request
    ) {
        self.requestID = requestID
        self.metadata = metadata
        self.request = request
    }
    #endif
}
