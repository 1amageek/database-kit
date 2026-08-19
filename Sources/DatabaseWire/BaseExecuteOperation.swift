#if DATABASE_KIT_MULTI_BASE
import DatabaseKit

public enum BaseExecuteOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.baseExecute

    public enum LifecycleState: UInt8, Sendable, Hashable {
        case provisioning = 0
        case active = 1
        case retiring = 2
        case retired = 3
        case moving = 4
        case deleting = 5
        case tombstone = 6
    }

    public struct PlacementDescription: Sendable, Hashable {
        public let id: Base.Placement.ID
        public let isDefault: Bool

        public init(id: Base.Placement.ID, isDefault: Bool) {
            self.id = id
            self.isDefault = isDefault
        }

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try id.encode(into: &writer)
            writer.writeBool(isDefault)
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                id: try Base.Placement.ID(from: &reader),
                isDefault: try reader.readBool()
            )
        }
    }

    public struct Description: Sendable, Hashable {
        public let id: Base.ID
        public let placementID: Base.Placement.ID
        public let placementGeneration: UInt64
        public let revision: UInt64
        public let lifecycle: LifecycleState

        public init(
            id: Base.ID,
            placementID: Base.Placement.ID,
            placementGeneration: UInt64,
            revision: UInt64,
            lifecycle: LifecycleState
        ) {
            self.id = id
            self.placementID = placementID
            self.placementGeneration = placementGeneration
            self.revision = revision
            self.lifecycle = lifecycle
        }

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try id.encode(into: &writer)
            try placementID.encode(into: &writer)
            writer.writeUInt64(placementGeneration)
            writer.writeUInt64(revision)
            writer.writeUInt8(lifecycle.rawValue)
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let id = try Base.ID(from: &reader)
            let placementID = try Base.Placement.ID(from: &reader)
            let placementGeneration = try reader.readUInt64()
            let revision = try reader.readUInt64()
            let rawLifecycle = try reader.readUInt8()
            guard let lifecycle = LifecycleState(rawValue: rawLifecycle) else {
                throw .invalidBaseLifecycleState(rawLifecycle)
            }
            self.init(
                id: id,
                placementID: placementID,
                placementGeneration: placementGeneration,
                revision: revision,
                lifecycle: lifecycle
            )
        }
    }

    public struct Plan: Sendable, Hashable {
        public enum Action: UInt8, Sendable, Hashable {
            case create = 0
            case retire = 1
            case activate = 2
            case delete = 3
            case move = 4
        }

        public let action: Action
        public let currentRevision: UInt64
        public let resultingRevision: UInt64
        public let destinationPlacementID: Base.Placement.ID?
        public let requiresJob: Bool

        public init(
            action: Action,
            currentRevision: UInt64,
            resultingRevision: UInt64,
            destinationPlacementID: Base.Placement.ID? = nil,
            requiresJob: Bool
        ) throws(DatabaseWireError) {
            guard resultingRevision > currentRevision else {
                throw .invalidBaseExecutionPlan
            }
            guard (action == .move) == (destinationPlacementID != nil) else {
                throw .invalidBaseExecutionPlan
            }
            self.action = action
            self.currentRevision = currentRevision
            self.resultingRevision = resultingRevision
            self.destinationPlacementID = destinationPlacementID
            self.requiresJob = requiresJob
        }

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeUInt8(action.rawValue)
            writer.writeUInt64(currentRevision)
            writer.writeUInt64(resultingRevision)
            writer.writeBool(destinationPlacementID != nil)
            if let destinationPlacementID {
                try destinationPlacementID.encode(into: &writer)
            }
            writer.writeBool(requiresJob)
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let rawAction = try reader.readUInt8()
            guard let action = Action(rawValue: rawAction) else {
                throw .invalidBaseExecutionPlan
            }
            try self.init(
                action: action,
                currentRevision: try reader.readUInt64(),
                resultingRevision: try reader.readUInt64(),
                destinationPlacementID: try reader.readBool()
                    ? try Base.Placement.ID(from: &reader)
                    : nil,
                requiresJob: try reader.readBool()
            )
        }
    }

    public enum Invocation: Sendable, Hashable {
        case placements
        case list
        case describe
        case create(
            baseID: Base.ID,
            placementID: Base.Placement.ID,
            initialGrants: [Security.Grant],
            expectedRevision: UInt64,
            idempotencyKey: String
        )
        case retire(expectedRevision: UInt64, idempotencyKey: String)
        case activate(expectedRevision: UInt64, idempotencyKey: String)
        case delete(expectedRevision: UInt64, idempotencyKey: String)
        case placementPlan(
            destination: Base.Placement.ID,
            expectedRevision: UInt64
        )
        case placementApply(
            destination: Base.Placement.ID,
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
            case .placements:
                writer.writeUInt8(0)
            case .list:
                writer.writeUInt8(1)
            case .describe:
                writer.writeUInt8(2)
            case .create(
                let baseID,
                let placementID,
                let initialGrants,
                let expectedRevision,
                let idempotencyKey
            ):
                writer.writeUInt8(3)
                try baseID.encode(into: &writer)
                try placementID.encode(into: &writer)
                try Self.encodeInitialGrants(
                    initialGrants,
                    for: baseID,
                    into: &writer
                )
                writer.writeUInt64(expectedRevision)
                try Self.encodeIdempotencyKey(idempotencyKey, into: &writer)
            case .retire(let expectedRevision, let idempotencyKey):
                writer.writeUInt8(4)
                writer.writeUInt64(expectedRevision)
                try Self.encodeIdempotencyKey(idempotencyKey, into: &writer)
            case .activate(let expectedRevision, let idempotencyKey):
                writer.writeUInt8(5)
                writer.writeUInt64(expectedRevision)
                try Self.encodeIdempotencyKey(idempotencyKey, into: &writer)
            case .delete(let expectedRevision, let idempotencyKey):
                writer.writeUInt8(6)
                writer.writeUInt64(expectedRevision)
                try Self.encodeIdempotencyKey(idempotencyKey, into: &writer)
            case .placementPlan(let destination, let expectedRevision):
                writer.writeUInt8(7)
                try destination.encode(into: &writer)
                writer.writeUInt64(expectedRevision)
            case .placementApply(
                let destination,
                let expectedRevision,
                let idempotencyKey
            ):
                writer.writeUInt8(8)
                try destination.encode(into: &writer)
                writer.writeUInt64(expectedRevision)
                try Self.encodeIdempotencyKey(idempotencyKey, into: &writer)
            }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0:
                self.init(invocation: .placements)
            case 1:
                self.init(invocation: .list)
            case 2:
                self.init(invocation: .describe)
            case 3:
                let baseID = try Base.ID(from: &reader)
                self.init(
                    invocation: .create(
                        baseID: baseID,
                        placementID: try Base.Placement.ID(from: &reader),
                        initialGrants: try Self.decodeInitialGrants(
                            for: baseID,
                            from: &reader
                        ),
                        expectedRevision: try reader.readUInt64(),
                        idempotencyKey: try Self.decodeIdempotencyKey(
                            from: &reader
                        )
                    )
                )
            case 4:
                self.init(
                    invocation: .retire(
                        expectedRevision: try reader.readUInt64(),
                        idempotencyKey: try Self.decodeIdempotencyKey(
                            from: &reader
                        )
                    )
                )
            case 5:
                self.init(
                    invocation: .activate(
                        expectedRevision: try reader.readUInt64(),
                        idempotencyKey: try Self.decodeIdempotencyKey(
                            from: &reader
                        )
                    )
                )
            case 6:
                self.init(
                    invocation: .delete(
                        expectedRevision: try reader.readUInt64(),
                        idempotencyKey: try Self.decodeIdempotencyKey(
                            from: &reader
                        )
                    )
                )
            case 7:
                self.init(
                    invocation: .placementPlan(
                        destination: try Base.Placement.ID(from: &reader),
                        expectedRevision: try reader.readUInt64()
                    )
                )
            case 8:
                self.init(
                    invocation: .placementApply(
                        destination: try Base.Placement.ID(from: &reader),
                        expectedRevision: try reader.readUInt64(),
                        idempotencyKey: try Self.decodeIdempotencyKey(
                            from: &reader
                        )
                    )
                )
            case let tag:
                throw .invalidBaseExecutionInvocation(tag)
            }
        }

        private static func encodeInitialGrants(
            _ grants: [Security.Grant],
            for baseID: Base.ID,
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try validateInitialGrants(grants, for: baseID)
            try writer.writeCount(grants.count)
            for grant in grants {
                try grant.encode(into: &writer)
            }
        }

        private static func decodeInitialGrants(
            for baseID: Base.ID,
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> [Security.Grant] {
            let count = try reader.readCount()
            var grants: [Security.Grant] = []
            grants.reserveCapacity(count)
            for _ in 0..<count {
                grants.append(try Security.Grant(from: &reader))
            }
            try validateInitialGrants(grants, for: baseID)
            return grants
        }

        private static func validateInitialGrants(
            _ grants: [Security.Grant],
            for baseID: Base.ID
        ) throws(DatabaseWireError) {
            guard !grants.isEmpty,
                  grants.contains(where: {
                      $0.resource == .base(baseID)
                          && $0.access.contains(.administer)
                  }),
                  grants.allSatisfy({ $0.resource == .base(baseID) }) else {
                throw .invalidInitialBaseGrants
            }
            try SecurityGrantCanonicalOrder.validate(grants)
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

    public enum Response: WireValue, Hashable {
        case placements([PlacementDescription])
        case bases([Description])
        case base(Description)
        case plan(Plan)
        case job(JobIdentity)

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .placements(let placements):
                try Self.validatePlacements(placements)
                writer.writeUInt8(0)
                try writer.writeCount(placements.count)
                for placement in placements {
                    try placement.encode(into: &writer)
                }
            case .bases(let bases):
                try Self.validateBases(bases)
                writer.writeUInt8(1)
                try writer.writeCount(bases.count)
                for base in bases {
                    try base.encode(into: &writer)
                }
            case .base(let base):
                writer.writeUInt8(2)
                try base.encode(into: &writer)
            case .plan(let plan):
                writer.writeUInt8(3)
                try plan.encode(into: &writer)
            case .job(let job):
                writer.writeUInt8(4)
                try job.encode(into: &writer)
            }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0:
                let count = try reader.readCount()
                var placements: [PlacementDescription] = []
                placements.reserveCapacity(count)
                for _ in 0..<count {
                    placements.append(try PlacementDescription(from: &reader))
                }
                try Self.validatePlacements(placements)
                self = .placements(placements)
            case 1:
                let count = try reader.readCount()
                var bases: [Description] = []
                bases.reserveCapacity(count)
                for _ in 0..<count {
                    bases.append(try Description(from: &reader))
                }
                try Self.validateBases(bases)
                self = .bases(bases)
            case 2:
                self = .base(try Description(from: &reader))
            case 3:
                self = .plan(try Plan(from: &reader))
            case 4:
                self = .job(try JobIdentity(from: &reader))
            case let tag:
                throw .invalidBaseExecutionResponse(tag)
            }
        }

        private static func validatePlacements(
            _ placements: [PlacementDescription]
        ) throws(DatabaseWireError) {
            var hasDefault = false
            for placement in placements where placement.isDefault {
                guard !hasDefault else {
                    throw .nonCanonicalPlacementSet
                }
                hasDefault = true
            }
            for (previous, current) in zip(
                placements,
                placements.dropFirst()
            ) {
                guard previous.id < current.id else {
                    throw .nonCanonicalPlacementSet
                }
            }
        }

        private static func validateBases(
            _ bases: [Description]
        ) throws(DatabaseWireError) {
            for (previous, current) in zip(bases, bases.dropFirst()) {
                guard previous.id < current.id else {
                    throw .nonCanonicalBaseSet
                }
            }
        }
    }
}

#endif
