import DatabaseTypes

public enum JobResultOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.jobResult
    public static let maximumResponsePageBytes = 512 * 1_024
    public static let maximumResponseBytes = 4 * 1_024 * 1_024

    public struct Continuation: WireValue, Hashable {
        public let job: JobIdentity
        public let responseDigest: JobResultDigest
        public let nextChunkIndex: UInt32

        public var jobID: DatabaseTypes.UUID { job.jobID }
        public var operation: JobOperationIdentifier { job.operation }

        public init(
            job: JobIdentity,
            responseDigest: JobResultDigest,
            nextChunkIndex: UInt32
        ) throws(DatabaseWireError) {
            guard nextChunkIndex > 0 else {
                throw .invalidResultPayload(0)
            }
            self.job = job
            self.responseDigest = responseDigest
            self.nextChunkIndex = nextChunkIndex
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            guard nextChunkIndex > 0 else {
                throw .invalidResultPayload(0)
            }
            try job.encode(into: &writer)
            try responseDigest.encode(into: &writer)
            writer.writeUInt32(nextChunkIndex)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            try self.init(
                job: JobIdentity(from: &reader),
                responseDigest: JobResultDigest(from: &reader),
                nextChunkIndex: reader.readUInt32()
            )
        }

        /// Detaches the digest from its response frame before paging continues.
        public func detached() -> Continuation {
            Continuation(
                validatedJob: job,
                responseDigest: responseDigest.detached(),
                nextChunkIndex: nextChunkIndex
            )
        }

        private init(
            validatedJob job: JobIdentity,
            responseDigest: JobResultDigest,
            nextChunkIndex: UInt32
        ) {
            self.job = job
            self.responseDigest = responseDigest
            self.nextChunkIndex = nextChunkIndex
        }
    }

    public struct Request: WireValue, Hashable {
        public let job: JobIdentity
        public let continuation: Continuation?

        public var jobID: DatabaseTypes.UUID { job.jobID }
        public var operation: JobOperationIdentifier { job.operation }

        public init(
            job: JobIdentity,
            continuation: Continuation? = nil
        ) {
            self.job = job
            self.continuation = continuation
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            if let continuation,
               continuation.job != job {
                throw .invalidResultPayload(2)
            }
            try job.encode(into: &writer)
            writer.writeBool(continuation != nil)
            if let continuation {
                try continuation.encode(into: &writer)
            }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let job = try JobIdentity(from: &reader)
            let continuation = try reader.readBool()
                ? try Continuation(from: &reader)
                : nil
            guard continuation == nil || continuation?.job == job else {
                throw .invalidResultPayload(2)
            }
            self.init(job: job, continuation: continuation)
        }
    }

    public enum Response: WireValue, Hashable {
        case succeeded(
            job: JobIdentity,
            responsePayloadPage: ByteString,
            totalResponseBytes: UInt64,
            responseDigest: JobResultDigest,
            continuation: Continuation?
        )
        case failed(job: JobIdentity, error: RemoteOperationError)
        case cancelled(job: JobIdentity)

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .succeeded(
                let job,
                let responsePayloadPage,
                let totalResponseBytes,
                let responseDigest,
                let continuation
            ):
                guard responsePayloadPage.count <= maximumResponsePageBytes else {
                    throw .byteStringTooLarge(
                        actual: responsePayloadPage.count,
                        maximum: maximumResponsePageBytes
                    )
                }
                guard totalResponseBytes <= UInt64(maximumResponseBytes),
                      totalResponseBytes >= UInt64(responsePayloadPage.count) else {
                    throw .byteCountOverflow
                }
                if let continuation,
                   (continuation.responseDigest != responseDigest
                    || continuation.job != job) {
                    throw .invalidResultPayload(1)
                }
                writer.writeUInt8(1)
                try job.encode(into: &writer)
                try writer.writeBytes(responsePayloadPage)
                writer.writeUInt64(totalResponseBytes)
                try responseDigest.encode(into: &writer)
                writer.writeBool(continuation != nil)
                if let continuation {
                    try continuation.encode(into: &writer)
                }
            case .failed(let job, let error):
                writer.writeUInt8(2)
                try job.encode(into: &writer)
                try error.encode(into: &writer)
            case .cancelled(let job):
                writer.writeUInt8(3)
                try job.encode(into: &writer)
            }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                let job = try JobIdentity(from: &reader)
                let responsePayloadPage = try reader.readBytes()
                let totalResponseBytes = try reader.readUInt64()
                let responseDigest = try JobResultDigest(from: &reader)
                let continuation = try reader.readBool()
                    ? try Continuation(from: &reader)
                    : nil
                guard responsePayloadPage.count
                        <= JobResultOperation.maximumResponsePageBytes else {
                    throw .byteStringTooLarge(
                        actual: responsePayloadPage.count,
                        maximum: JobResultOperation.maximumResponsePageBytes
                    )
                }
                guard totalResponseBytes
                        <= UInt64(JobResultOperation.maximumResponseBytes),
                      totalResponseBytes
                        >= UInt64(responsePayloadPage.count) else {
                    throw .byteCountOverflow
                }
                if let continuation,
                   (continuation.responseDigest != responseDigest
                    || continuation.job != job) {
                    throw .invalidResultPayload(1)
                }
                self = .succeeded(
                    job: job,
                    responsePayloadPage: responsePayloadPage,
                    totalResponseBytes: totalResponseBytes,
                    responseDigest: responseDigest,
                    continuation: continuation
                )
            case 2:
                self = .failed(
                    job: try JobIdentity(from: &reader),
                    error: try RemoteOperationError(from: &reader)
                )
            case 3:
                self = .cancelled(
                    job: try JobIdentity(from: &reader)
                )
            case let tag:
                throw .invalidResultPayload(tag)
            }
        }
    }
}
