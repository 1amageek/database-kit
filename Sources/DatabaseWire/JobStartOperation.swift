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
        #if DATABASE_KIT_MULTIPLE_BASES
        public let target: DatabaseOperationTarget
        #endif
        public let operation: JobOperationIdentifier
        public let requestPayload: ByteString
        public let maximumSliceWorkUnits: UInt64
        public let retryPolicy: RetryPolicy

        #if DATABASE_KIT_MULTIPLE_BASES
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
        #else
        public init(
            operation: JobOperationIdentifier,
            requestPayload: ByteString,
            maximumSliceWorkUnits: UInt64 = 100_000,
            retryPolicy: RetryPolicy = RetryPolicy()
        ) {
            self.operation = operation
            self.requestPayload = requestPayload
            self.maximumSliceWorkUnits = maximumSliceWorkUnits
            self.retryPolicy = retryPolicy
        }
        #endif

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            #if DATABASE_KIT_MULTIPLE_BASES
            try target.encode(into: &writer)
            #endif
            try operation.encode(into: &writer)
            try writer.writeBytes(requestPayload)
            writer.writeUInt64(maximumSliceWorkUnits)
            try retryPolicy.encode(into: &writer)
        }

        #if DATABASE_KIT_MULTIPLE_BASES
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
        #else
        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                operation: try JobOperationIdentifier(from: &reader),
                requestPayload: try reader.readBytes(),
                maximumSliceWorkUnits: try reader.readUInt64(),
                retryPolicy: try RetryPolicy(from: &reader)
            )
        }
        #endif
    }

    public struct Response: WireValue, Hashable {
        public let job: JobIdentity

        public var jobID: DatabaseTypes.UUID { job.jobID }
        public var operation: JobOperationIdentifier { job.operation }
        #if DATABASE_KIT_MULTIPLE_BASES
        public var target: DatabaseOperationTarget { job.target }
        #endif

        public init(job: JobIdentity) {
            self.job = job
        }

        #if DATABASE_KIT_MULTIPLE_BASES
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
        #else
        public init(
            jobID: DatabaseTypes.UUID,
            operation: JobOperationIdentifier
        ) {
            self.init(
                job: JobIdentity(jobID: jobID, operation: operation)
            )
        }
        #endif

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
