import DatabaseTypes

public enum JobStatusOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.jobStatus

    public enum State: UInt8, Sendable, Hashable {
        case pending = 1
        case running = 2
        case committingUnsuccessfulOutcome = 3
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

    public struct Request: WireValue, Hashable {
        public let job: JobIdentity

        public var jobID: DatabaseTypes.UUID { job.jobID }
        public var operation: JobOperationIdentifier { job.operation }

        public init(job: JobIdentity) {
            self.job = job
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

    public struct Response: WireValue, Hashable {
        public let state: State
        public let job: JobIdentity
        public let completedWorkUnits: UInt64
        public let totalWorkUnits: UInt64?
        public let executionCount: UInt64
        public let currentSliceAttempt: UInt32
        public let unsuccessfulOutcomeCommitAttempt: UInt64
        public let lastUnsuccessfulOutcomeCommitError: RemoteOperationError?
        public let cancellationRequested: Bool
        public let nextAttemptAt: Timestamp?
        public let updatedAt: Timestamp

        public var operation: JobOperationIdentifier { job.operation }

        public init(
            state: State,
            job: JobIdentity,
            completedWorkUnits: UInt64,
            totalWorkUnits: UInt64? = nil,
            executionCount: UInt64,
            currentSliceAttempt: UInt32,
            unsuccessfulOutcomeCommitAttempt: UInt64 = 0,
            lastUnsuccessfulOutcomeCommitError: RemoteOperationError? = nil,
            cancellationRequested: Bool = false,
            nextAttemptAt: Timestamp? = nil,
            updatedAt: Timestamp
        ) throws(DatabaseWireError) {
            try Self.validate(
                state: state,
                completedWorkUnits: completedWorkUnits,
                totalWorkUnits: totalWorkUnits,
                executionCount: executionCount,
                currentSliceAttempt: currentSliceAttempt,
                unsuccessfulOutcomeCommitAttempt:
                    unsuccessfulOutcomeCommitAttempt,
                lastUnsuccessfulOutcomeCommitError:
                    lastUnsuccessfulOutcomeCommitError,
                cancellationRequested: cancellationRequested,
                nextAttemptAt: nextAttemptAt,
                updatedAt: updatedAt
            )
            self.state = state
            self.job = job
            self.completedWorkUnits = completedWorkUnits
            self.totalWorkUnits = totalWorkUnits
            self.executionCount = executionCount
            self.currentSliceAttempt = currentSliceAttempt
            self.unsuccessfulOutcomeCommitAttempt =
                unsuccessfulOutcomeCommitAttempt
            self.lastUnsuccessfulOutcomeCommitError =
                lastUnsuccessfulOutcomeCommitError
            self.cancellationRequested = cancellationRequested
            self.nextAttemptAt = nextAttemptAt
            self.updatedAt = updatedAt
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeUInt8(state.rawValue)
            try job.encode(into: &writer)
            writer.writeUInt64(completedWorkUnits)
            writer.writeBool(totalWorkUnits != nil)
            if let totalWorkUnits { writer.writeUInt64(totalWorkUnits) }
            writer.writeUInt64(executionCount)
            writer.writeUInt32(currentSliceAttempt)
            writer.writeUInt64(unsuccessfulOutcomeCommitAttempt)
            writer.writeBool(lastUnsuccessfulOutcomeCommitError != nil)
            if let lastUnsuccessfulOutcomeCommitError {
                try lastUnsuccessfulOutcomeCommitError.encode(into: &writer)
            }
            writer.writeBool(cancellationRequested)
            writer.writeBool(nextAttemptAt != nil)
            if let nextAttemptAt {
                try nextAttemptAt.encode(into: &writer)
            }
            try updatedAt.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let state = try State(from: &reader)
            let job = try JobIdentity(from: &reader)
            let completedWorkUnits = try reader.readUInt64()
            let totalWorkUnits = try reader.readBool()
                ? try reader.readUInt64()
                : nil
            try self.init(
                state: state,
                job: job,
                completedWorkUnits: completedWorkUnits,
                totalWorkUnits: totalWorkUnits,
                executionCount: try reader.readUInt64(),
                currentSliceAttempt: try reader.readUInt32(),
                unsuccessfulOutcomeCommitAttempt: try reader.readUInt64(),
                lastUnsuccessfulOutcomeCommitError: try reader.readBool()
                    ? try RemoteOperationError(from: &reader)
                    : nil,
                cancellationRequested: try reader.readBool(),
                nextAttemptAt: try reader.readBool()
                    ? try Timestamp(from: &reader)
                    : nil,
                updatedAt: try Timestamp(from: &reader)
            )
        }

        private static func validate(
            state: State,
            completedWorkUnits: UInt64,
            totalWorkUnits: UInt64?,
            executionCount: UInt64,
            currentSliceAttempt: UInt32,
            unsuccessfulOutcomeCommitAttempt: UInt64,
            lastUnsuccessfulOutcomeCommitError: RemoteOperationError?,
            cancellationRequested: Bool,
            nextAttemptAt: Timestamp?,
            updatedAt: Timestamp
        ) throws(DatabaseWireError) {
            guard executionCount >= UInt64(currentSliceAttempt),
                  totalWorkUnits.map({ $0 >= completedWorkUnits }) ?? true,
                  nextAttemptAt.map({ $0 >= updatedAt }) ?? true else {
                throw .invalidJobStatus
            }
            let hasUnsuccessfulOutcomeCommitDiagnostic =
                lastUnsuccessfulOutcomeCommitError != nil
            switch state {
            case .pending:
                guard unsuccessfulOutcomeCommitAttempt == 0,
                      !hasUnsuccessfulOutcomeCommitDiagnostic,
                      !cancellationRequested,
                      nextAttemptAt != nil else {
                    throw .invalidJobStatus
                }
            case .running:
                guard currentSliceAttempt > 0,
                      unsuccessfulOutcomeCommitAttempt == 0,
                      !hasUnsuccessfulOutcomeCommitDiagnostic,
                      nextAttemptAt == nil else {
                    throw .invalidJobStatus
                }
            case .committingUnsuccessfulOutcome:
                guard !cancellationRequested,
                      unsuccessfulOutcomeCommitAttempt > 0
                        || nextAttemptAt != nil,
                      unsuccessfulOutcomeCommitAttempt > 0
                        || !hasUnsuccessfulOutcomeCommitDiagnostic,
                      nextAttemptAt == nil
                        || (unsuccessfulOutcomeCommitAttempt == 0)
                            == !hasUnsuccessfulOutcomeCommitDiagnostic else {
                    throw .invalidJobStatus
                }
            case .succeeded:
                guard unsuccessfulOutcomeCommitAttempt == 0,
                      !hasUnsuccessfulOutcomeCommitDiagnostic,
                      !cancellationRequested,
                      nextAttemptAt == nil else {
                    throw .invalidJobStatus
                }
            case .failed, .cancelled:
                guard unsuccessfulOutcomeCommitAttempt > 0,
                      !hasUnsuccessfulOutcomeCommitDiagnostic,
                      !cancellationRequested,
                      nextAttemptAt == nil else {
                    throw .invalidJobStatus
                }
            }
        }
    }
}
