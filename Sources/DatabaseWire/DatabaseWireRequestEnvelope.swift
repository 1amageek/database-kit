import DatabaseTypes

public struct DatabaseWireRequestEnvelope: Sendable, Hashable {
    public let requestID: UInt64
    public let operation: DatabaseOperationIdentifier
    #if DATABASE_KIT_MULTI_BASE
    public let target: DatabaseOperationTarget
    #endif
    public let metadata: OperationRequestMetadata
    public let payload: ByteString
    let payloadAdmission: DatabaseWireReader.AdmissionContext?

    #if DATABASE_KIT_MULTI_BASE
    init(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        target: DatabaseOperationTarget,
        metadata: OperationRequestMetadata = OperationRequestMetadata(),
        payload: ByteString,
        payloadAdmission: DatabaseWireReader.AdmissionContext? = nil
    ) {
        self.requestID = requestID
        self.operation = operation
        self.target = target
        self.metadata = metadata
        self.payload = payload
        self.payloadAdmission = payloadAdmission
    }
    #else
    init(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        metadata: OperationRequestMetadata = OperationRequestMetadata(),
        payload: ByteString,
        payloadAdmission: DatabaseWireReader.AdmissionContext? = nil
    ) {
        self.requestID = requestID
        self.operation = operation
        self.metadata = metadata
        self.payload = payload
        self.payloadAdmission = payloadAdmission
    }
    #endif

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.requestID == rhs.requestID, lhs.operation == rhs.operation,
              lhs.metadata == rhs.metadata, lhs.payload == rhs.payload else { return false }
        #if DATABASE_KIT_MULTI_BASE
        return lhs.target == rhs.target
        #else
        return true
        #endif
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(requestID)
        hasher.combine(operation)
        #if DATABASE_KIT_MULTI_BASE
        hasher.combine(target)
        #endif
        hasher.combine(metadata)
        hasher.combine(payload)
    }
}
