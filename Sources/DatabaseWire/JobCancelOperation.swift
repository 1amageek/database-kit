import DatabaseTypes

public enum JobCancelOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.jobCancel

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
        public let job: JobIdentity
        public let state: JobStatusOperation.State
        public let accepted: Bool

        public init(
            job: JobIdentity,
            state: JobStatusOperation.State,
            accepted: Bool
        ) throws(DatabaseWireError) {
            switch (accepted, state) {
            case (true, .running),
                 (true, .committingUnsuccessfulOutcome),
                 (false, .running),
                 (false, .committingUnsuccessfulOutcome),
                 (false, .succeeded),
                 (false, .failed),
                 (false, .cancelled):
                break
            case (_, .pending),
                 (true, .succeeded),
                 (true, .failed),
                 (true, .cancelled):
                throw .invalidJobCancellationResponse
            }
            self.job = job
            self.state = state
            self.accepted = accepted
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try job.encode(into: &writer)
            writer.writeUInt8(state.rawValue)
            writer.writeBool(accepted)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let job = try JobIdentity(from: &reader)
            let rawValue = try reader.readUInt8()
            guard let state = JobStatusOperation.State(rawValue: rawValue) else {
                throw .invalidValueTag(rawValue)
            }
            try self.init(
                job: job,
                state: state,
                accepted: try reader.readBool()
            )
        }
    }
}
