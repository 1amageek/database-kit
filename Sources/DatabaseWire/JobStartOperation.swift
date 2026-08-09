import DatabaseTypes

public enum JobStartOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.jobStart

    public struct RetryPolicy: WireValue, Hashable {
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

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeUInt32(maximumAttempts)
            writer.writeUInt32(initialBackoffMilliseconds)
            writer.writeUInt32(maximumBackoffMilliseconds)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                maximumAttempts: try reader.readUInt32(),
                initialBackoffMilliseconds: try reader.readUInt32(),
                maximumBackoffMilliseconds: try reader.readUInt32()
            )
        }
    }

    public struct Request: WireValue, Hashable {
        public let target: DatabaseOperationTarget
        public let operation: JobOperationIdentifier
        public let requestPayload: ByteString
        public let maximumSliceWorkUnits: UInt64
        public let retryPolicy: RetryPolicy

        public init(
            target: DatabaseOperationTarget,
            operation: JobOperationIdentifier,
            requestPayload: ByteString,
            maximumSliceWorkUnits: UInt64 = 100_000,
            retryPolicy: RetryPolicy = RetryPolicy()
        ) {
            self.target = target
            self.operation = operation
            self.requestPayload = requestPayload
            self.maximumSliceWorkUnits = maximumSliceWorkUnits
            self.retryPolicy = retryPolicy
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try target.encode(into: &writer)
            try operation.encode(into: &writer)
            try writer.writeBytes(requestPayload)
            writer.writeUInt64(maximumSliceWorkUnits)
            try retryPolicy.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                target: try DatabaseOperationTarget(from: &reader),
                operation: try JobOperationIdentifier(from: &reader),
                requestPayload: try reader.readBytes(),
                maximumSliceWorkUnits: try reader.readUInt64(),
                retryPolicy: try RetryPolicy(from: &reader)
            )
        }
    }

    public struct Response: WireValue, Hashable {
        public let job: JobIdentity

        public var jobID: DatabaseTypes.UUID { job.jobID }
        public var operation: JobOperationIdentifier { job.operation }
        public var target: DatabaseOperationTarget { job.target }

        public init(job: JobIdentity) {
            self.job = job
        }

        public init(
            jobID: DatabaseTypes.UUID,
            operation: JobOperationIdentifier,
            target: DatabaseOperationTarget
        ) {
            self.init(
                job: JobIdentity(
                    jobID: jobID,
                    operation: operation,
                    target: target
                )
            )
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try job.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(job: try JobIdentity(from: &reader))
        }
    }
}
