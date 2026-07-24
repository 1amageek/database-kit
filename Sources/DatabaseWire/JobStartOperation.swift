import DatabaseTypes
import DatabaseValue

public enum JobStartOperation: DatabaseOperation {
    public static let identifier = DatabaseOperationIdentifier.jobStart

    public struct RetryPolicy: DatabaseWireValue, Hashable {
        public let maximumAttempts: UInt32
        public let initialBackoffMilliseconds: UInt32
        public let maximumBackoffMilliseconds: UInt32

        public init(
            maximumAttempts: UInt32 = 3,
            initialBackoffMilliseconds: UInt32 = 1_000,
            maximumBackoffMilliseconds: UInt32 = 60_000
        ) {
            self.maximumAttempts = maximumAttempts
            self.initialBackoffMilliseconds = initialBackoffMilliseconds
            self.maximumBackoffMilliseconds = maximumBackoffMilliseconds
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeUInt32(maximumAttempts)
            writer.writeUInt32(initialBackoffMilliseconds)
            writer.writeUInt32(maximumBackoffMilliseconds)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                maximumAttempts: try reader.readUInt32(),
                initialBackoffMilliseconds: try reader.readUInt32(),
                maximumBackoffMilliseconds: try reader.readUInt32()
            )
        }
    }

    public struct Request: DatabaseWireValue, Hashable {
        public let operation: DatabaseJobOperationIdentifier
        public let requestPayload: ByteString
        public let maximumSliceWorkUnits: UInt64
        public let retryPolicy: RetryPolicy

        public init(
            operation: DatabaseJobOperationIdentifier,
            requestPayload: ByteString,
            maximumSliceWorkUnits: UInt64 = 100_000,
            retryPolicy: RetryPolicy = RetryPolicy()
        ) {
            self.operation = operation
            self.requestPayload = requestPayload
            self.maximumSliceWorkUnits = maximumSliceWorkUnits
            self.retryPolicy = retryPolicy
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try operation.encode(into: &writer)
            try writer.writeBytes(requestPayload)
            writer.writeUInt64(maximumSliceWorkUnits)
            try retryPolicy.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                operation: try DatabaseJobOperationIdentifier(from: &reader),
                requestPayload: try reader.readBytes(),
                maximumSliceWorkUnits: try reader.readUInt64(),
                retryPolicy: try RetryPolicy(from: &reader)
            )
        }
    }

    public struct Response: DatabaseWireValue, Hashable {
        public let job: DatabaseJobIdentity

        public var jobID: DatabaseTypes.UUID { job.jobID }
        public var operation: DatabaseJobOperationIdentifier { job.operation }

        public init(job: DatabaseJobIdentity) {
            self.job = job
        }

        public init(
            jobID: DatabaseTypes.UUID,
            operation: DatabaseJobOperationIdentifier
        ) {
            self.init(
                job: DatabaseJobIdentity(jobID: jobID, operation: operation)
            )
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try job.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(job: try DatabaseJobIdentity(from: &reader))
        }
    }
}
