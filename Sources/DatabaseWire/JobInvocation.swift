import DatabaseTypes
/// Encodes a declared job request directly into the outer `job.start` frame.
public struct JobInvocation<Job: DatabaseJobDescriptor>:
    DatabaseWireValue {
    public let request: Job.Request
    public let maximumSliceWorkUnits: UInt64
    public let retryPolicy: JobStartOperation.RetryPolicy

    public init(
        request: Job.Request,
        maximumSliceWorkUnits: UInt64 = 100_000,
        retryPolicy: JobStartOperation.RetryPolicy = .init()
    ) {
        self.request = request
        self.maximumSliceWorkUnits = maximumSliceWorkUnits
        self.retryPolicy = retryPolicy
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try Job.jobOperationIdentifier().encode(into: &writer)
        try writer.writeLengthPrefixed {
            (payloadWriter: inout DatabaseWireWriter)
                throws(DatabaseWireError) in
            try request.encode(into: &payloadWriter)
        }
        writer.writeUInt64(maximumSliceWorkUnits)
        try retryPolicy.encode(into: &writer)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let operation = try DatabaseJobOperationIdentifier(from: &reader)
        guard operation == (try Job.jobOperationIdentifier()) else {
            throw .mismatchedJobOperationIdentifier
        }
        let request = try reader.readLengthPrefixed {
            (payloadReader: inout DatabaseWireReader)
                throws(DatabaseWireError) in
            try Job.Request(from: &payloadReader)
        }
        self.init(
            request: request,
            maximumSliceWorkUnits: try reader.readUInt64(),
            retryPolicy: try JobStartOperation.RetryPolicy(from: &reader)
        )
    }
}
