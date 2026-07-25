import DatabaseTypes
import DatabaseKit

public enum MutationExecuteOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.mutationExecute

    public enum Kind: UInt8, Sendable, Hashable {
        case insert = 1
        case update = 2
        case upsert = 3
        case delete = 4

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let rawValue = try reader.readUInt8()
            guard let value = Self(rawValue: rawValue) else {
                throw .invalidValueTag(rawValue)
            }
            self = value
        }
    }

    public struct Change: Sendable, Hashable {
        public let kind: Kind
        public let identity: EntityReference
        public let fields: FieldObject

        public init(
            kind: Kind,
            identity: EntityReference,
            fields: FieldObject = FieldObject()
        ) {
            self.kind = kind
            self.identity = identity
            self.fields = fields
        }

        fileprivate func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            writer.writeUInt8(kind.rawValue)
            try identity.encode(into: &writer)
            try fields.encode(into: &writer)
        }

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let kind = try Kind(from: &reader)
            let identity = try EntityReference(from: &reader)
            self.init(
                kind: kind,
                identity: identity,
                fields: try FieldObject(from: &reader)
            )
        }
    }

    public enum Input: Sendable, Hashable {
        case entities([Change])
        case statement(
            QueryExecuteOperation.Input,
            parameters: [QueryParameter]
        )

        fileprivate func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            switch self {
            case .entities(let changes):
                writer.writeUInt8(1)
                try writer.writeCount(changes.count)
                for change in changes { try change.encode(into: &writer) }
            case .statement(let input, let parameters):
                writer.writeUInt8(2)
                try input.encode(into: &writer)
                try writer.writeCount(parameters.count)
                for parameter in parameters { try parameter.encode(into: &writer) }
            }
        }

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                let count = try reader.readCount()
                var changes: [Change] = []
                changes.reserveCapacity(count)
                for _ in 0..<count { changes.append(try Change(from: &reader)) }
                self = .entities(changes)
            case 2:
                let input = try QueryExecuteOperation.Input(from: &reader)
                let count = try reader.readCount()
                var parameters: [QueryParameter] = []
                parameters.reserveCapacity(count)
                for _ in 0..<count {
                    parameters.append(try QueryParameter(from: &reader))
                }
                self = .statement(input, parameters: parameters)
            case let tag:
                throw .invalidQueryInput(tag)
            }
        }
    }

    public enum Precondition: Sendable, Hashable {
        case expectedVersion(identity: EntityReference, version: ByteString)
        case mustExist(EntityReference)
        case mustNotExist(EntityReference)

        fileprivate func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            switch self {
            case .expectedVersion(let identity, let version):
                writer.writeUInt8(1)
                try identity.encode(into: &writer)
                try writer.writeBytes(version)
            case .mustExist(let identity):
                writer.writeUInt8(2)
                try identity.encode(into: &writer)
            case .mustNotExist(let identity):
                writer.writeUInt8(3)
                try identity.encode(into: &writer)
            }
        }

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                self = .expectedVersion(
                    identity: try EntityReference(from: &reader),
                    version: try reader.readBytes()
                )
            case 2:
                self = .mustExist(try EntityReference(from: &reader))
            case 3:
                self = .mustNotExist(try EntityReference(from: &reader))
            case let tag:
                throw .invalidValueTag(tag)
            }
        }
    }

    public struct Request: WireValue, Hashable {
        public let input: Input
        public let preconditions: [Precondition]
        public let graphPartitions: FieldObject
        public let budget: ExecutionBudget

        public init(
            input: Input,
            preconditions: [Precondition] = [],
            graphPartitions: FieldObject = FieldObject(),
            budget: ExecutionBudget = ExecutionBudget()
        ) {
            self.input = input
            self.preconditions = preconditions
            self.graphPartitions = graphPartitions
            self.budget = budget
        }

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try input.encode(into: &writer)
            try writer.writeCount(preconditions.count)
            for precondition in preconditions { try precondition.encode(into: &writer) }
            try graphPartitions.encode(into: &writer)
            try budget.encode(into: &writer)
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let input = try Input(from: &reader)
            let count = try reader.readCount()
            var preconditions: [Precondition] = []
            preconditions.reserveCapacity(count)
            for _ in 0..<count { preconditions.append(try Precondition(from: &reader)) }
            self.init(
                input: input,
                preconditions: preconditions,
                graphPartitions: try FieldObject(from: &reader),
                budget: try ExecutionBudget(from: &reader)
            )
        }
    }

    public struct EntityEffect: WireValue, Hashable {
        public let kind: Kind
        public let identity: EntityReference
        public let version: ByteString?

        public init(
            kind: Kind,
            identity: EntityReference,
            version: ByteString? = nil
        ) {
            self.kind = kind
            self.identity = identity
            self.version = version
        }

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            writer.writeUInt8(kind.rawValue)
            try identity.encode(into: &writer)
            try writer.writeOptionalBytes(version)
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            self.init(
                kind: try Kind(from: &reader),
                identity: try EntityReference(from: &reader),
                version: try reader.readOptionalBytes()
            )
        }
    }

    /// Aggregate effect of one atomic RDF dataset update.
    ///
    /// Counts describe physical logical quads and explicit graph catalog
    /// entries. Duplicate INSERTs and deletes of absent quads do not increment
    /// the corresponding count.
    public struct RDFEffect: WireValue, Hashable {
        public let insertedQuads: UInt64
        public let deletedQuads: UInt64
        public let createdGraphs: UInt64
        public let droppedGraphs: UInt64

        public init(
            insertedQuads: UInt64 = 0,
            deletedQuads: UInt64 = 0,
            createdGraphs: UInt64 = 0,
            droppedGraphs: UInt64 = 0
        ) {
            self.insertedQuads = insertedQuads
            self.deletedQuads = deletedQuads
            self.createdGraphs = createdGraphs
            self.droppedGraphs = droppedGraphs
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeUInt64(insertedQuads)
            writer.writeUInt64(deletedQuads)
            writer.writeUInt64(createdGraphs)
            writer.writeUInt64(droppedGraphs)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                insertedQuads: try reader.readUInt64(),
                deletedQuads: try reader.readUInt64(),
                createdGraphs: try reader.readUInt64(),
                droppedGraphs: try reader.readUInt64()
            )
        }
    }

    public enum Result: WireValue, Hashable {
        case entities([EntityEffect])
        case rdf(RDFEffect)

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .entities(let effects):
                writer.writeUInt8(1)
                try writer.writeCount(effects.count)
                for effect in effects {
                    try effect.encode(into: &writer)
                }
            case .rdf(let effect):
                writer.writeUInt8(2)
                try effect.encode(into: &writer)
            }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                let count = try reader.readCount()
                var effects: [EntityEffect] = []
                effects.reserveCapacity(count)
                for _ in 0..<count {
                    effects.append(try EntityEffect(from: &reader))
                }
                self = .entities(effects)
            case 2:
                self = .rdf(try RDFEffect(from: &reader))
            case let tag:
                throw .invalidValueTag(tag)
            }
        }
    }

    public struct Response: WireValue, Hashable {
        public let commitVersion: UInt64
        public let result: Result

        public init(commitVersion: UInt64, result: Result) {
            self.commitVersion = commitVersion
            self.result = result
        }

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            writer.writeUInt64(commitVersion)
            try result.encode(into: &writer)
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let commitVersion = try reader.readUInt64()
            self.init(
                commitVersion: commitVersion,
                result: try Result(from: &reader)
            )
        }
    }
}
