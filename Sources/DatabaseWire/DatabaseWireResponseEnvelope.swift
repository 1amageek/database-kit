import DatabaseTypes
struct DatabaseWireResponseEnvelope: Sendable, Hashable {
    public let requestID: UInt64
    public let operation: DatabaseOperationIdentifier
    public let payload: DatabaseWireResponsePayload
    let payloadAdmission: DatabaseWireReader.AdmissionContext?

    public init(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        payload: DatabaseWireResponsePayload
    ) {
        self.init(requestID: requestID, operation: operation, payload: payload, payloadAdmission: nil)
    }

    init(
        requestID: UInt64,
        operation: DatabaseOperationIdentifier,
        payload: DatabaseWireResponsePayload,
        payloadAdmission: DatabaseWireReader.AdmissionContext?
    ) {
        self.requestID = requestID
        self.operation = operation
        self.payload = payload
        self.payloadAdmission = payloadAdmission
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.requestID == rhs.requestID && lhs.operation == rhs.operation && lhs.payload == rhs.payload
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(requestID)
        hasher.combine(operation)
        hasher.combine(payload)
    }
}
