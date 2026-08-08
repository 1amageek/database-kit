import DatabaseKit
import DatabaseTypes

public enum SchemaExecuteOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.schemaExecute

    public enum Invocation: Sendable, Hashable {
        case plan(
            manifest: SchemaManifest,
            expectedFingerprint: SchemaFingerprint?
        )
        case apply(
            manifest: SchemaManifest,
            expectedFingerprint: SchemaFingerprint,
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
            case .plan(let manifest, let expectedFingerprint):
                writer.writeUInt8(0)
                try manifest.encode(into: &writer)
                writer.writeBool(expectedFingerprint != nil)
                if let expectedFingerprint {
                    try expectedFingerprint.encode(into: &writer)
                }
            case .apply(
                let manifest,
                let expectedFingerprint,
                let idempotencyKey
            ):
                guard !idempotencyKey.isEmpty else {
                    throw .invalidSchemaManifest(
                        "Schema apply idempotency key must not be empty"
                    )
                }
                writer.writeUInt8(1)
                try manifest.encode(into: &writer)
                try expectedFingerprint.encode(into: &writer)
                try writer.writeString(idempotencyKey)
            }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0:
                let manifest = try SchemaManifest(from: &reader)
                let expected = try reader.readBool()
                    ? SchemaFingerprint(from: &reader)
                    : nil
                self.init(
                    invocation: .plan(
                        manifest: manifest,
                        expectedFingerprint: expected
                    )
                )
            case 1:
                let manifest = try SchemaManifest(from: &reader)
                let expected = try SchemaFingerprint(from: &reader)
                let idempotencyKey = try reader.readString()
                guard !idempotencyKey.isEmpty else {
                    throw .invalidSchemaManifest(
                        "Schema apply idempotency key must not be empty"
                    )
                }
                self.init(
                    invocation: .apply(
                        manifest: manifest,
                        expectedFingerprint: expected,
                        idempotencyKey: idempotencyKey
                    )
                )
            case let tag:
                throw .invalidSchemaExecutionInvocation(tag)
            }
        }
    }

    public enum Compatibility: UInt8, Sendable, Hashable {
        case initial = 0
        case compatible = 1
        case requiresMigration = 2
    }

    public struct CompatibilityIssue: Sendable, Hashable {
        public let code: String
        public let path: String
        public let message: String

        public init(code: String, path: String, message: String) {
            self.code = code
            self.path = path
            self.message = message
        }

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeString(code)
            try writer.writeString(path)
            try writer.writeString(message)
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                code: try reader.readString(),
                path: try reader.readString(),
                message: try reader.readString()
            )
        }
    }

    public struct Plan: Sendable, Hashable {
        public let currentFingerprint: SchemaFingerprint?
        public let targetFingerprint: SchemaFingerprint
        public let compatibility: Compatibility
        public let issues: [CompatibilityIssue]

        public init(
            currentFingerprint: SchemaFingerprint?,
            targetFingerprint: SchemaFingerprint,
            compatibility: Compatibility,
            issues: [CompatibilityIssue]
        ) {
            self.currentFingerprint = currentFingerprint
            self.targetFingerprint = targetFingerprint
            self.compatibility = compatibility
            self.issues = issues
        }

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeBool(currentFingerprint != nil)
            if let currentFingerprint {
                try currentFingerprint.encode(into: &writer)
            }
            try targetFingerprint.encode(into: &writer)
            writer.writeUInt8(compatibility.rawValue)
            try writer.writeCount(issues.count)
            for issue in issues {
                try issue.encode(into: &writer)
            }
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let current = try reader.readBool()
                ? SchemaFingerprint(from: &reader)
                : nil
            let target = try SchemaFingerprint(from: &reader)
            let rawCompatibility = try reader.readUInt8()
            guard let compatibility = Compatibility(
                rawValue: rawCompatibility
            ) else {
                throw .invalidSchemaCompatibility(rawCompatibility)
            }
            let issueCount = try reader.readCount()
            var issues: [CompatibilityIssue] = []
            issues.reserveCapacity(issueCount)
            for _ in 0..<issueCount {
                issues.append(try CompatibilityIssue(from: &reader))
            }
            self.init(
                currentFingerprint: current,
                targetFingerprint: target,
                compatibility: compatibility,
                issues: issues
            )
        }
    }

    public struct Applied: Sendable, Hashable {
        public let previousFingerprint: SchemaFingerprint?
        public let fingerprint: SchemaFingerprint
        public let schemaVersion: SchemaVersion
        public let generation: UInt64
        public let job: JobIdentity?

        public init(
            previousFingerprint: SchemaFingerprint?,
            fingerprint: SchemaFingerprint,
            schemaVersion: SchemaVersion,
            generation: UInt64,
            job: JobIdentity? = nil
        ) {
            self.previousFingerprint = previousFingerprint
            self.fingerprint = fingerprint
            self.schemaVersion = schemaVersion
            self.generation = generation
            self.job = job
        }

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeBool(previousFingerprint != nil)
            if let previousFingerprint {
                try previousFingerprint.encode(into: &writer)
            }
            try fingerprint.encode(into: &writer)
            try schemaVersion.encode(into: &writer)
            writer.writeUInt64(generation)
            writer.writeBool(job != nil)
            if let job {
                try job.encode(into: &writer)
            }
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                previousFingerprint: try reader.readBool()
                    ? SchemaFingerprint(from: &reader)
                    : nil,
                fingerprint: try SchemaFingerprint(from: &reader),
                schemaVersion: try SchemaVersion(from: &reader),
                generation: try reader.readUInt64(),
                job: try reader.readBool()
                    ? JobIdentity(from: &reader)
                    : nil
            )
        }
    }

    public enum Response: WireValue, Hashable {
        case plan(Plan)
        case applied(Applied)

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .plan(let plan):
                writer.writeUInt8(0)
                try plan.encode(into: &writer)
            case .applied(let applied):
                writer.writeUInt8(1)
                try applied.encode(into: &writer)
            }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0: self = .plan(try Plan(from: &reader))
            case 1: self = .applied(try Applied(from: &reader))
            case let tag: throw .invalidSchemaExecutionResponse(tag)
            }
        }
    }
}
