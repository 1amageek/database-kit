import DatabaseTypes
import DatabaseKit

public enum MutationExecuteOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.mutationExecute

    public enum Input: Sendable, Hashable {
        case entities([EntityMutationChange])
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
                var changes: [EntityMutationChange] = []
                changes.reserveCapacity(count)
                for _ in 0..<count {
                    changes.append(try EntityMutationChange(from: &reader))
                }
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

    public struct Request: WireValue, Hashable {
        public let input: Input
        public let preconditions: [EntityMutationPrecondition]
        public let graphPartitions: FieldObject
        public let budget: ExecutionBudget

        public init(
            input: Input,
            preconditions: [EntityMutationPrecondition] = [],
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
            var preconditions: [EntityMutationPrecondition] = []
            preconditions.reserveCapacity(count)
            for _ in 0..<count {
                preconditions.append(
                    try EntityMutationPrecondition(from: &reader)
                )
            }
            self.init(
                input: input,
                preconditions: preconditions,
                graphPartitions: try FieldObject(from: &reader),
                budget: try ExecutionBudget(from: &reader)
            )
        }
    }

    public enum Result: WireValue, Hashable {
        case entities([EntityMutationEffect])
        case rdf(RDFMutationEffect)

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
                var effects: [EntityMutationEffect] = []
                effects.reserveCapacity(count)
                for _ in 0..<count {
                    effects.append(try EntityMutationEffect(from: &reader))
                }
                self = .entities(effects)
            case 2:
                self = .rdf(try RDFMutationEffect(from: &reader))
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

private extension RDFMutationEffect {
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

private extension EntityMutationKind {
    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        let rawValue = try reader.readUInt8()
        guard let value = Self(rawValue: rawValue) else {
            throw .invalidValueTag(rawValue)
        }
        self = value
    }
}

private extension EntityMutationChange {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt8(kind.rawValue)
        try identity.encode(into: &writer)
        try fields.encode(into: &writer)
    }

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self.init(
            kind: try EntityMutationKind(from: &reader),
            identity: try EntityReference(from: &reader),
            fields: try FieldObject(from: &reader)
        )
    }
}

private extension EntityMutationPrecondition {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
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

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
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

private extension EntityMutationEffect {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt8(kind.rawValue)
        try identity.encode(into: &writer)
        try writer.writeOptionalBytes(version)
    }

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self.init(
            kind: try EntityMutationKind(from: &reader),
            identity: try EntityReference(from: &reader),
            version: try reader.readOptionalBytes()
        )
    }
}
