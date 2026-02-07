import Foundation

/// Versioned message envelope for client-server communication
///
/// Uses string-based `operationID` instead of enum for forward compatibility.
/// New operations can be added without breaking existing decoders.
///
/// `metadata` carries extensible headers (auth tokens, tenant IDs, trace IDs)
/// that load balancers can inspect without deserializing `payload`.
public struct ServiceEnvelope: Sendable, Codable {

    /// Protocol version for forward/backward compatibility
    public let version: Int

    /// Unique request correlation ID
    public let requestID: String

    /// Operation identifier: "fetch", "save", "schema", "get", "count", "delete"
    public let operationID: String

    /// JSON-encoded operation-specific body
    public let payload: Data

    /// Extensible headers (authorization, tenantID, traceID, etc.)
    public let metadata: [String: String]

    // MARK: - Response fields

    /// Whether this envelope represents an error response
    public let isError: Bool?

    /// Error code (when isError == true)
    public let errorCode: String?

    /// Error message (when isError == true)
    public let errorMessage: String?

    // MARK: - Initializers

    /// Create a request envelope
    public init(
        operationID: String,
        payload: Data = Data(),
        metadata: [String: String] = [:],
        requestID: String = UUID().uuidString,
        version: Int = 1
    ) {
        self.version = version
        self.requestID = requestID
        self.operationID = operationID
        self.payload = payload
        self.metadata = metadata
        self.isError = nil
        self.errorCode = nil
        self.errorMessage = nil
    }

    /// Create a success response envelope
    public init(
        responseTo requestID: String,
        operationID: String,
        payload: Data = Data(),
        metadata: [String: String] = [:],
        version: Int = 1
    ) {
        self.version = version
        self.requestID = requestID
        self.operationID = operationID
        self.payload = payload
        self.metadata = metadata
        self.isError = false
        self.errorCode = nil
        self.errorMessage = nil
    }

    /// Create an error response envelope
    public init(
        responseTo requestID: String,
        operationID: String,
        errorCode: String,
        errorMessage: String,
        metadata: [String: String] = [:],
        version: Int = 1
    ) {
        self.version = version
        self.requestID = requestID
        self.operationID = operationID
        self.payload = Data()
        self.metadata = metadata
        self.isError = true
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}

/// Typed error for service-level failures
public struct ServiceError: Sendable, Codable, Error {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
