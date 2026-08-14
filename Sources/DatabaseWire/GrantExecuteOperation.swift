#if DATABASE_KIT_MULTIPLE_BASES
import DatabaseKit

public enum GrantExecuteOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.grantExecute

    public enum Invocation: Sendable, Hashable {
        case direct(subject: Security.Subject?)
        case effective
        case grant(
            Security.Grant,
            expectedRevision: UInt64,
            idempotencyKey: String
        )
        case revoke(
            Security.Grant,
            expectedRevision: UInt64,
            idempotencyKey: String
        )
    }

    public struct Request: WireValue, Hashable {
        public let invocation: Invocation

        public init(invocation: Invocation) {
            self.invocation = invocation
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch invocation {
            case .direct(let subject):
                writer.writeUInt8(0)
                writer.writeBool(subject != nil)
                if let subject {
                    try subject.encode(into: &writer)
                }
            case .effective:
                writer.writeUInt8(1)
            case .grant(
                let grant,
                let expectedRevision,
                let idempotencyKey
            ):
                writer.writeUInt8(2)
                try grant.encode(into: &writer)
                writer.writeUInt64(expectedRevision)
                try Self.encodeIdempotencyKey(idempotencyKey, into: &writer)
            case .revoke(
                let grant,
                let expectedRevision,
                let idempotencyKey
            ):
                writer.writeUInt8(3)
                try grant.encode(into: &writer)
                writer.writeUInt64(expectedRevision)
                try Self.encodeIdempotencyKey(idempotencyKey, into: &writer)
            }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0:
                self.init(
                    invocation: .direct(
                        subject: try reader.readBool()
                            ? try Security.Subject(from: &reader)
                            : nil
                    )
                )
            case 1:
                self.init(invocation: .effective)
            case 2:
                self.init(
                    invocation: .grant(
                        try Security.Grant(from: &reader),
                        expectedRevision: try reader.readUInt64(),
                        idempotencyKey: try Self.decodeIdempotencyKey(
                            from: &reader
                        )
                    )
                )
            case 3:
                self.init(
                    invocation: .revoke(
                        try Security.Grant(from: &reader),
                        expectedRevision: try reader.readUInt64(),
                        idempotencyKey: try Self.decodeIdempotencyKey(
                            from: &reader
                        )
                    )
                )
            case let tag:
                throw .invalidGrantExecutionInvocation(tag)
            }
        }

        private static func encodeIdempotencyKey(
            _ idempotencyKey: String,
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            guard !idempotencyKey.isEmpty else {
                throw .emptyIdempotencyKey
            }
            try writer.writeString(idempotencyKey)
        }

        private static func decodeIdempotencyKey(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> String {
            let idempotencyKey = try reader.readString()
            guard !idempotencyKey.isEmpty else {
                throw .emptyIdempotencyKey
            }
            return idempotencyKey
        }
    }

    public struct DirectGrantSet: Sendable, Hashable {
        public let revision: UInt64
        public let grants: [Security.Grant]

        public init(
            revision: UInt64,
            grants: [Security.Grant]
        ) {
            self.revision = revision
            self.grants = grants
        }

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try SecurityGrantCanonicalOrder.validate(grants)
            writer.writeUInt64(revision)
            try writer.writeCount(grants.count)
            for grant in grants {
                try grant.encode(into: &writer)
            }
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let revision = try reader.readUInt64()
            let count = try reader.readCount()
            var grants: [Security.Grant] = []
            grants.reserveCapacity(count)
            for _ in 0..<count {
                grants.append(try Security.Grant(from: &reader))
            }
            try SecurityGrantCanonicalOrder.validate(grants)
            self.init(revision: revision, grants: grants)
        }
    }

    public struct EffectiveGrantSet: Sendable, Hashable {
        public let access: Security.Access
        public let contributors: [Security.Grant]

        public init(
            access: Security.Access,
            contributors: [Security.Grant]
        ) {
            self.access = access
            self.contributors = contributors
        }

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try SecurityGrantCanonicalOrder.validate(contributors)
            try access.encode(into: &writer)
            try writer.writeCount(contributors.count)
            for contributor in contributors {
                try contributor.encode(into: &writer)
            }
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let access = try Security.Access(from: &reader)
            let count = try reader.readCount()
            var contributors: [Security.Grant] = []
            contributors.reserveCapacity(count)
            for _ in 0..<count {
                contributors.append(try Security.Grant(from: &reader))
            }
            try SecurityGrantCanonicalOrder.validate(contributors)
            self.init(access: access, contributors: contributors)
        }
    }

    public enum Response: WireValue, Hashable {
        case direct(DirectGrantSet)
        case effective(EffectiveGrantSet)
        case mutated(revision: UInt64)

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .direct(let grants):
                writer.writeUInt8(0)
                try grants.encode(into: &writer)
            case .effective(let grants):
                writer.writeUInt8(1)
                try grants.encode(into: &writer)
            case .mutated(let revision):
                writer.writeUInt8(2)
                writer.writeUInt64(revision)
            }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0:
                self = .direct(try DirectGrantSet(from: &reader))
            case 1:
                self = .effective(try EffectiveGrantSet(from: &reader))
            case 2:
                self = .mutated(revision: try reader.readUInt64())
            case let tag:
                throw .invalidGrantExecutionResponse(tag)
            }
        }
    }
}

#endif
