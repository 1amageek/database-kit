import DatabaseTypes

public enum JobCancelOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.jobCancel

    public struct Request: DatabaseWireValue, Hashable {
        public let job: DatabaseJobIdentity

        public var jobID: DatabaseTypes.UUID { job.jobID }
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
        public let job: DatabaseJobIdentity
        public let state: JobStatusOperation.State
        public let accepted: Bool

        public init(
            job: DatabaseJobIdentity,
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

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try job.encode(into: &writer)
            writer.writeUInt8(state.rawValue)
            writer.writeBool(accepted)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let job = try DatabaseJobIdentity(from: &reader)
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
