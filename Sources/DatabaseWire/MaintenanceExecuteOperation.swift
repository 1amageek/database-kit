import DatabaseTypes
import DatabaseValue

public enum MaintenanceExecuteOperation: DatabaseOperation {
    public static let identifier = DatabaseOperationIdentifier.maintenanceExecute

    public enum Invocation: Sendable, Hashable {
        case migrationStatus
        case runMigrations(targetVersion: DatabaseSchemaVersion?)
        case indexStatus(
            entity: String?,
            index: String?,
            partitions: FieldObject
        )
        case rebuildIndex(
            entity: String,
            index: String,
            partitions: FieldObject,
            batchSize: UInt32
        )
        case compact

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .migrationStatus:
                writer.writeUInt8(1)
            case .runMigrations(let targetVersion):
                writer.writeUInt8(2)
                writer.writeBool(targetVersion != nil)
                if let targetVersion { try targetVersion.encode(into: &writer) }
            case .indexStatus(let entity, let index, let partitions):
                writer.writeUInt8(3)
                try writer.writeOptionalString(entity)
                try writer.writeOptionalString(index)
                try Self.encode(partitions: partitions, into: &writer)
            case .rebuildIndex(
                let entity,
                let index,
                let partitions,
                let batchSize
            ):
                writer.writeUInt8(4)
                try writer.writeString(entity)
                try writer.writeString(index)
                try Self.encode(partitions: partitions, into: &writer)
                writer.writeUInt32(batchSize)
            case .compact:
                writer.writeUInt8(5)
            }
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                self = .migrationStatus
            case 2:
                self = .runMigrations(
                    targetVersion: try reader.readBool()
                        ? try DatabaseSchemaVersion(from: &reader)
                        : nil
                )
            case 3:
                self = .indexStatus(
                    entity: try reader.readOptionalString(),
                    index: try reader.readOptionalString(),
                    partitions: try Self.decodePartitions(from: &reader)
                )
            case 4:
                self = .rebuildIndex(
                    entity: try reader.readString(),
                    index: try reader.readString(),
                    partitions: try Self.decodePartitions(from: &reader),
                    batchSize: try reader.readUInt32()
                )
            case 5:
                self = .compact
            case let tag:
                throw .invalidValueTag(tag)
            }
        }

        private static func encode(
            partitions: FieldObject,
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try partitions.encode(into: &writer)
        }

        private static func decodePartitions(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> FieldObject {
            try FieldObject(from: &reader)
        }
    }

    public struct Request: DatabaseWireValue, Hashable {
        public let invocation: Invocation
        public let continuation: ByteString?
        public let budget: DatabaseExecutionBudget

        public init(
            invocation: Invocation,
            continuation: ByteString? = nil,
            budget: DatabaseExecutionBudget = DatabaseExecutionBudget()
        ) {
            self.invocation = invocation
            self.continuation = continuation
            self.budget = budget
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try invocation.encode(into: &writer)
            try writer.writeOptionalBytes(continuation)
            try budget.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                invocation: try Invocation(from: &reader),
                continuation: try reader.readOptionalBytes(),
                budget: try DatabaseExecutionBudget(from: &reader)
            )
        }
    }

    public struct MigrationStatus: DatabaseWireValue, Hashable {
        public let currentVersion: DatabaseSchemaVersion?
        public let targetVersion: DatabaseSchemaVersion
        public let pendingMigrationIdentifiers: [String]

        public init(
            currentVersion: DatabaseSchemaVersion?,
            targetVersion: DatabaseSchemaVersion,
            pendingMigrationIdentifiers: [String]
        ) {
            self.currentVersion = currentVersion
            self.targetVersion = targetVersion
            self.pendingMigrationIdentifiers = pendingMigrationIdentifiers
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeBool(currentVersion != nil)
            if let currentVersion {
                try currentVersion.encode(into: &writer)
            }
            try targetVersion.encode(into: &writer)
            try writer.writeCount(pendingMigrationIdentifiers.count)
            for identifier in pendingMigrationIdentifiers {
                try writer.writeString(identifier)
            }
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let currentVersion = try reader.readBool()
                ? try DatabaseSchemaVersion(from: &reader)
                : nil
            let targetVersion = try DatabaseSchemaVersion(from: &reader)
            let count = try reader.readCount()
            var identifiers: [String] = []
            identifiers.reserveCapacity(count)
            for _ in 0..<count {
                identifiers.append(try reader.readString())
            }
            self.init(
                currentVersion: currentVersion,
                targetVersion: targetVersion,
                pendingMigrationIdentifiers: identifiers
            )
        }
    }

    public enum IndexState: UInt8, Sendable, Hashable {
        case ready = 1
        case building = 2
        case stale = 3
        case failed = 4

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

    public struct IndexStatus: DatabaseWireValue, Hashable {
        public let entity: String
        public let index: String
        public let partitions: FieldObject
        public let state: IndexState
        public let indexedEntityCount: UInt64
        public let detail: String?

        public init(
            entity: String,
            index: String,
            partitions: FieldObject,
            state: IndexState,
            indexedEntityCount: UInt64,
            detail: String? = nil
        ) {
            self.entity = entity
            self.index = index
            self.partitions = partitions
            self.state = state
            self.indexedEntityCount = indexedEntityCount
            self.detail = detail
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeString(entity)
            try writer.writeString(index)
            try partitions.encode(into: &writer)
            writer.writeUInt8(state.rawValue)
            writer.writeUInt64(indexedEntityCount)
            try writer.writeOptionalString(detail)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let entity = try reader.readString()
            let index = try reader.readString()
            self.init(
                entity: entity,
                index: index,
                partitions: try FieldObject(from: &reader),
                state: try IndexState(from: &reader),
                indexedEntityCount: try reader.readUInt64(),
                detail: try reader.readOptionalString()
            )
        }
    }

    public struct IndexStatusPage: DatabaseWireValue, Hashable {
        public let indexes: [IndexStatus]
        public let continuation: ByteString?

        public init(indexes: [IndexStatus], continuation: ByteString? = nil) {
            self.indexes = indexes
            self.continuation = continuation
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeCount(indexes.count)
            for index in indexes { try index.encode(into: &writer) }
            try writer.writeOptionalBytes(continuation)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let count = try reader.readCount()
            var indexes: [IndexStatus] = []
            indexes.reserveCapacity(count)
            for _ in 0..<count {
                indexes.append(try IndexStatus(from: &reader))
            }
            self.init(
                indexes: indexes,
                continuation: try reader.readOptionalBytes()
            )
        }
    }

    public enum ExecutionKind: UInt8, Sendable, Hashable {
        case migrations = 1
        case indexRebuild = 2
        case compaction = 3

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

    public struct ExecutionResult: DatabaseWireValue, Hashable {
        public let kind: ExecutionKind
        public let completedWorkUnits: UInt64
        public let commitVersion: UInt64?
        public let isComplete: Bool
        public let continuation: ByteString?

        public init(
            kind: ExecutionKind,
            completedWorkUnits: UInt64,
            commitVersion: UInt64? = nil,
            isComplete: Bool,
            continuation: ByteString? = nil
        ) {
            self.kind = kind
            self.completedWorkUnits = completedWorkUnits
            self.commitVersion = commitVersion
            self.isComplete = isComplete
            self.continuation = continuation
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeUInt8(kind.rawValue)
            writer.writeUInt64(completedWorkUnits)
            writer.writeBool(commitVersion != nil)
            if let commitVersion { writer.writeUInt64(commitVersion) }
            writer.writeBool(isComplete)
            try writer.writeOptionalBytes(continuation)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                kind: try ExecutionKind(from: &reader),
                completedWorkUnits: try reader.readUInt64(),
                commitVersion: try reader.readBool() ? try reader.readUInt64() : nil,
                isComplete: try reader.readBool(),
                continuation: try reader.readOptionalBytes()
            )
        }
    }

    public enum Response: DatabaseWireValue, Hashable {
        case migrationStatus(MigrationStatus)
        case indexStatus(IndexStatusPage)
        case execution(ExecutionResult)

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .migrationStatus(let value):
                writer.writeUInt8(1)
                try value.encode(into: &writer)
            case .indexStatus(let value):
                writer.writeUInt8(2)
                try value.encode(into: &writer)
            case .execution(let value):
                writer.writeUInt8(3)
                try value.encode(into: &writer)
            }
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1: self = .migrationStatus(try MigrationStatus(from: &reader))
            case 2: self = .indexStatus(try IndexStatusPage(from: &reader))
            case 3: self = .execution(try ExecutionResult(from: &reader))
            case let tag: throw .invalidResultPayload(tag)
            }
        }
    }
}
