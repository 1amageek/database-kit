import DatabaseTypes

public enum SHACLExecuteOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.shaclExecute

    public enum Entailment: Sendable, Hashable {
        case none
        case rdfs
        case owl(ontology: String)

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .none:
                writer.writeUInt8(1)
            case .rdfs:
                writer.writeUInt8(2)
            case .owl(let ontology):
                writer.writeUInt8(3)
                try writer.writeString(ontology)
            }
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                self = .none
            case 2:
                self = .rdfs
            case 3:
                self = .owl(ontology: try reader.readString())
            case let tag:
                throw .invalidValueTag(tag)
            }
        }
    }

    public enum DataGraph: Sendable, Hashable {
        case defaultGraph
        case named(RDFTerm)

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .defaultGraph:
                writer.writeUInt8(1)
            case .named(let graph):
                writer.writeUInt8(2)
                try graph.encode(into: &writer)
            }
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                self = .defaultGraph
            case 2:
                self = .named(try RDFTerm(from: &reader))
            case let tag:
                throw .invalidValueTag(tag)
            }
        }
    }

    public struct DataSource: DatabaseWireValue, Hashable {
        public let entity: String
        public let index: String
        public let partitions: FieldObject
        public let graph: DataGraph

        public init(
            entity: String,
            index: String,
            partitions: FieldObject = FieldObject(),
            graph: DataGraph
        ) {
            self.entity = entity
            self.index = index
            self.partitions = partitions
            self.graph = graph
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeString(entity)
            try writer.writeString(index)
            try partitions.encode(into: &writer)
            try graph.encode(into: &writer)
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
                graph: try DataGraph(from: &reader)
            )
        }
    }

    public enum Focus: Sendable, Hashable {
        case targets
        case nodes([RDFTerm])
        case entities([EntityReference])

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .targets:
                writer.writeUInt8(1)
            case .nodes(let nodes):
                writer.writeUInt8(2)
                try writer.writeCount(nodes.count)
                for node in nodes {
                    try node.encode(into: &writer)
                }
            case .entities(let identities):
                writer.writeUInt8(3)
                try writer.writeCount(identities.count)
                for identity in identities {
                    try identity.encode(into: &writer)
                }
            }
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                self = .targets
            case 2:
                let count = try reader.readCount()
                var nodes: [RDFTerm] = []
                nodes.reserveCapacity(count)
                for _ in 0..<count {
                    nodes.append(try RDFTerm(from: &reader))
                }
                self = .nodes(nodes)
            case 3:
                let count = try reader.readCount()
                var identities: [EntityReference] = []
                identities.reserveCapacity(count)
                for _ in 0..<count {
                    identities.append(try EntityReference(from: &reader))
                }
                self = .entities(identities)
            case let tag:
                throw .invalidValueTag(tag)
            }
        }
    }

    public enum Invocation: Sendable, Hashable {
        case describeShapes(graph: String)
        case upsertShapes(
            graph: String,
            shapes: [RDFQuadValue],
            expectedRevision: UInt64?
        )
        case deleteShapes(graph: String, expectedRevision: UInt64?)
        case validate(
            shapesGraph: String,
            data: DataSource,
            focus: Focus,
            entailment: Entailment
        )

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .describeShapes(let graph):
                writer.writeUInt8(1)
                try writer.writeString(graph)
            case .upsertShapes(let graph, let shapes, let expectedRevision):
                writer.writeUInt8(2)
                try writer.writeString(graph)
                try writer.writeCount(shapes.count)
                for shape in shapes { try shape.encode(into: &writer) }
                Self.encodeRevision(expectedRevision, into: &writer)
            case .deleteShapes(let graph, let expectedRevision):
                writer.writeUInt8(3)
                try writer.writeString(graph)
                Self.encodeRevision(expectedRevision, into: &writer)
            case .validate(
                let shapesGraph,
                let data,
                let focus,
                let entailment
            ):
                writer.writeUInt8(4)
                try writer.writeString(shapesGraph)
                try data.encode(into: &writer)
                try focus.encode(into: &writer)
                try entailment.encode(into: &writer)
            }
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                self = .describeShapes(graph: try reader.readString())
            case 2:
                let graph = try reader.readString()
                let count = try reader.readCount()
                var shapes: [RDFQuadValue] = []
                shapes.reserveCapacity(count)
                for _ in 0..<count {
                    shapes.append(try RDFQuadValue(from: &reader))
                }
                self = .upsertShapes(
                    graph: graph,
                    shapes: shapes,
                    expectedRevision: try Self.decodeRevision(from: &reader)
                )
            case 3:
                self = .deleteShapes(
                    graph: try reader.readString(),
                    expectedRevision: try Self.decodeRevision(from: &reader)
                )
            case 4:
                let shapesGraph = try reader.readString()
                let data = try DataSource(from: &reader)
                self = .validate(
                    shapesGraph: shapesGraph,
                    data: data,
                    focus: try Focus(from: &reader),
                    entailment: try Entailment(from: &reader)
                )
            case let tag:
                throw .invalidValueTag(tag)
            }
        }

        private static func encodeRevision(
            _ revision: UInt64?,
            into writer: inout DatabaseWireWriter
        ) {
            writer.writeBool(revision != nil)
            if let revision { writer.writeUInt64(revision) }
        }

        private static func decodeRevision(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> UInt64? {
            try reader.readBool() ? try reader.readUInt64() : nil
        }
    }

    public struct Request: DatabaseWireValue, Hashable {
        public let invocation: Invocation
        public let page: QueryExecuteOperation.Page
        public let budget: ExecutionBudget

        public init(
            invocation: Invocation,
            page: QueryExecuteOperation.Page = QueryExecuteOperation.Page(),
            budget: ExecutionBudget = ExecutionBudget()
        ) {
            self.invocation = invocation
            self.page = page
            self.budget = budget
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try invocation.encode(into: &writer)
            try page.encode(into: &writer)
            try budget.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                invocation: try Invocation(from: &reader),
                page: try QueryExecuteOperation.Page(from: &reader),
                budget: try ExecutionBudget(from: &reader)
            )
        }
    }

    public struct ShapesPage: DatabaseWireValue, Hashable {
        public let graph: String
        public let revision: UInt64
        public let shapes: [RDFQuadValue]
        public let continuation: ByteString?

        public init(
            graph: String,
            revision: UInt64,
            shapes: [RDFQuadValue],
            continuation: ByteString? = nil
        ) {
            self.graph = graph
            self.revision = revision
            self.shapes = shapes
            self.continuation = continuation
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeString(graph)
            writer.writeUInt64(revision)
            try writer.writeCount(shapes.count)
            for shape in shapes { try shape.encode(into: &writer) }
            try writer.writeOptionalBytes(continuation)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let graph = try reader.readString()
            let revision = try reader.readUInt64()
            let count = try reader.readCount()
            var shapes: [RDFQuadValue] = []
            shapes.reserveCapacity(count)
            for _ in 0..<count {
                shapes.append(try RDFQuadValue(from: &reader))
            }
            self.init(
                graph: graph,
                revision: revision,
                shapes: shapes,
                continuation: try reader.readOptionalBytes()
            )
        }
    }

    public enum Response: DatabaseWireValue, Hashable {
        case shapes(ShapesPage)
        case mutation(RevisionMutationResult)
        case validation(ValidationReport)

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .shapes(let value):
                writer.writeUInt8(1)
                try value.encode(into: &writer)
            case .mutation(let value):
                writer.writeUInt8(2)
                try value.encode(into: &writer)
            case .validation(let value):
                writer.writeUInt8(3)
                try value.encode(into: &writer)
            }
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1: self = .shapes(try ShapesPage(from: &reader))
            case 2: self = .mutation(try RevisionMutationResult(from: &reader))
            case 3: self = .validation(try ValidationReport(from: &reader))
            case let tag: throw .invalidResultPayload(tag)
            }
        }
    }
}
