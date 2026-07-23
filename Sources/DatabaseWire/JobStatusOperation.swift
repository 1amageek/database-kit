public import DatabaseValue

public enum JobStatusOperation: DatabaseOperation {
    public static let identifier = DatabaseOperationIdentifier.jobStatus

    public enum State: UInt8, Sendable, Hashable {
        case pending = 1
        case running = 2
        case committingOutcome = 3
        case succeeded = 4
        case failed = 5
        case cancelled = 6

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let rawValue = try reader.readUInt8()
            guard let value = Self(rawValue: rawValue) else {
                throw .invalidValueTag(rawValue)
            }
            self = value
        }
    }

    public struct Request: DatabaseWireValue, Hashable {
        public let job: DatabaseJobIdentity

        public var jobID: DatabaseUUID { job.jobID }
        public var operation: DatabaseJobOperationIdentifier { job.operation }

        public init(job: DatabaseJobIdentity) {
            self.job = job
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

    public struct Response: DatabaseWireValue, Hashable {
        public let state: State
        public let job: DatabaseJobIdentity
        public let completedWorkUnits: UInt64
        public let totalWorkUnits: UInt64?
        public let executionCount: UInt64
        public let currentSliceAttempt: UInt32
        public let terminalOutcomeCommitAttempt: UInt64
        public let terminalOutcomeCommitError: DatabaseRemoteError?
        public let cancellationRequested: Bool
        public let nextAttemptAt: DatabaseTimestamp?
        public let updatedAt: DatabaseTimestamp

        public var operation: DatabaseJobOperationIdentifier { job.operation }

        public init(
            state: State,
            job: DatabaseJobIdentity,
            completedWorkUnits: UInt64,
            totalWorkUnits: UInt64? = nil,
            executionCount: UInt64,
            currentSliceAttempt: UInt32,
            terminalOutcomeCommitAttempt: UInt64 = 0,
            terminalOutcomeCommitError: DatabaseRemoteError? = nil,
            cancellationRequested: Bool = false,
            nextAttemptAt: DatabaseTimestamp? = nil,
            updatedAt: DatabaseTimestamp
        ) {
            self.state = state
            self.job = job
            self.completedWorkUnits = completedWorkUnits
            self.totalWorkUnits = totalWorkUnits
            self.executionCount = executionCount
            self.currentSliceAttempt = currentSliceAttempt
            self.terminalOutcomeCommitAttempt = terminalOutcomeCommitAttempt
            self.terminalOutcomeCommitError = terminalOutcomeCommitError
            self.cancellationRequested = cancellationRequested
            self.nextAttemptAt = nextAttemptAt
            self.updatedAt = updatedAt
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeUInt8(state.rawValue)
            try job.encode(into: &writer)
            writer.writeUInt64(completedWorkUnits)
            writer.writeBool(totalWorkUnits != nil)
            if let totalWorkUnits { writer.writeUInt64(totalWorkUnits) }
            writer.writeUInt64(executionCount)
            writer.writeUInt32(currentSliceAttempt)
            writer.writeUInt64(terminalOutcomeCommitAttempt)
            writer.writeBool(terminalOutcomeCommitError != nil)
            if let terminalOutcomeCommitError {
                try terminalOutcomeCommitError.encode(into: &writer)
            }
            writer.writeBool(cancellationRequested)
            writer.writeBool(nextAttemptAt != nil)
            if let nextAttemptAt {
                try nextAttemptAt.encode(into: &writer)
            }
            try updatedAt.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let state = try State(from: &reader)
            let job = try DatabaseJobIdentity(from: &reader)
            let completedWorkUnits = try reader.readUInt64()
            let totalWorkUnits = try reader.readBool()
                ? try reader.readUInt64()
                : nil
            self.init(
                state: state,
                job: job,
                completedWorkUnits: completedWorkUnits,
                totalWorkUnits: totalWorkUnits,
                executionCount: try reader.readUInt64(),
                currentSliceAttempt: try reader.readUInt32(),
                terminalOutcomeCommitAttempt: try reader.readUInt64(),
                terminalOutcomeCommitError: try reader.readBool()
                    ? try DatabaseRemoteError(from: &reader)
                    : nil,
                cancellationRequested: try reader.readBool(),
                nextAttemptAt: try reader.readBool()
                    ? try DatabaseTimestamp(from: &reader)
                    : nil,
                updatedAt: try DatabaseTimestamp(from: &reader)
            )
        }
    }
}
