public import DatabaseValue
public import QueryIR

public enum QueryExecuteOperation: DatabaseOperation {
    public static let identifier = DatabaseOperationIdentifier.queryExecute

    public enum Language: UInt8, Sendable, Hashable {
        case sql = 1
        case sparql = 2

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let rawValue = try reader.readUInt8()
            guard let value = Self(rawValue: rawValue) else {
                throw .invalidQueryLanguage(rawValue)
            }
            self = value
        }
    }

    public enum Input: Sendable, Hashable {
        case text(language: Language, statement: String)
        case ir(QueryStatement)

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            switch self {
            case .text(let language, let statement):
                writer.writeUInt8(1)
                writer.writeUInt8(language.rawValue)
                try writer.writeString(statement)
            case .ir(let statement):
                writer.writeUInt8(2)
                try QueryIRWireCodec.encodeStatement(statement, into: &writer)
            }
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                self = .text(
                    language: try Language(from: &reader),
                    statement: try reader.readString()
                )
            case 2:
                self = .ir(try QueryIRWireCodec.decodeStatement(from: &reader))
            case let tag:
                throw .invalidQueryInput(tag)
            }
        }
    }

    public struct Page: DatabaseWireValue, Hashable {
        public let limit: UInt32
        public let continuation: DatabaseBytes?

        public init(limit: UInt32 = 1_000, continuation: DatabaseBytes? = nil) {
            self.limit = limit
            self.continuation = continuation
        }

        public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            writer.writeUInt32(limit)
            try writer.writeOptionalBytes(continuation)
        }

        public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            self.init(limit: try reader.readUInt32(), continuation: try reader.readOptionalBytes())
        }
    }

    public struct Request: DatabaseWireValue, Hashable {
        public let input: Input
        public let parameters: [DatabaseObjectField]
        public let graphPartitions: [DatabaseObjectField]
        public let page: Page
        public let budget: DatabaseExecutionBudget

        public init(
            input: Input,
            parameters: [DatabaseObjectField] = [],
            graphPartitions: [DatabaseObjectField] = [],
            page: Page = Page(),
            budget: DatabaseExecutionBudget = DatabaseExecutionBudget()
        ) {
            self.input = input
            self.parameters = parameters
            self.graphPartitions = graphPartitions
            self.page = page
            self.budget = budget
        }

        public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try input.encode(into: &writer)
            try writer.writeCount(parameters.count)
            for parameter in parameters { try parameter.encode(into: &writer) }
            try writer.writeCount(graphPartitions.count)
            for partition in graphPartitions { try partition.encode(into: &writer) }
            try page.encode(into: &writer)
            try budget.encode(into: &writer)
        }

        public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let input = try Input(from: &reader)
            let count = try reader.readCount()
            var parameters: [DatabaseObjectField] = []
            parameters.reserveCapacity(count)
            for _ in 0..<count {
                parameters.append(try DatabaseObjectField(from: &reader))
            }
            let graphPartitionCount = try reader.readCount()
            var graphPartitions: [DatabaseObjectField] = []
            graphPartitions.reserveCapacity(graphPartitionCount)
            for _ in 0..<graphPartitionCount {
                graphPartitions.append(try DatabaseObjectField(from: &reader))
            }
            self.init(
                input: input,
                parameters: parameters,
                graphPartitions: graphPartitions,
                page: try Page(from: &reader),
                budget: try DatabaseExecutionBudget(from: &reader)
            )
        }
    }

    public struct Row: Sendable, Hashable {
        public let values: [DatabaseObjectField]
        public let annotations: [DatabaseObjectField]
        public let version: DatabaseBytes?

        public init(
            values: [DatabaseObjectField],
            annotations: [DatabaseObjectField] = [],
            version: DatabaseBytes? = nil
        ) {
            self.values = values
            self.annotations = annotations
            self.version = version
        }

        fileprivate func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try writer.writeCount(values.count)
            for value in values { try value.encode(into: &writer) }
            try writer.writeCount(annotations.count)
            for annotation in annotations { try annotation.encode(into: &writer) }
            try writer.writeOptionalBytes(version)
        }

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let valueCount = try reader.readCount()
            var values: [DatabaseObjectField] = []
            values.reserveCapacity(valueCount)
            for _ in 0..<valueCount { values.append(try DatabaseObjectField(from: &reader)) }
            let annotationCount = try reader.readCount()
            var annotations: [DatabaseObjectField] = []
            annotations.reserveCapacity(annotationCount)
            for _ in 0..<annotationCount {
                annotations.append(try DatabaseObjectField(from: &reader))
            }
            self.init(
                values: values,
                annotations: annotations,
                version: try reader.readOptionalBytes()
            )
        }
    }

    public struct RowPage: Sendable, Hashable {
        public let rows: [Row]
        public let continuation: DatabaseBytes?
        public let snapshotVersion: UInt64?

        public init(rows: [Row], continuation: DatabaseBytes? = nil, snapshotVersion: UInt64? = nil) {
            self.rows = rows
            self.continuation = continuation
            self.snapshotVersion = snapshotVersion
        }

        fileprivate func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try writer.writeCount(rows.count)
            for row in rows { try row.encode(into: &writer) }
            try writer.writeOptionalBytes(continuation)
            if let snapshotVersion {
                writer.writeBool(true)
                writer.writeUInt64(snapshotVersion)
            } else {
                writer.writeBool(false)
            }
        }

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let count = try reader.readCount()
            var rows: [Row] = []
            rows.reserveCapacity(count)
            for _ in 0..<count { rows.append(try Row(from: &reader)) }
            let continuation = try reader.readOptionalBytes()
            let snapshotVersion = try reader.readBool() ? try reader.readUInt64() : nil
            self.init(rows: rows, continuation: continuation, snapshotVersion: snapshotVersion)
        }
    }

    public struct GraphPage: Sendable, Hashable {
        public let triples: [DatabaseRDFQuad]
        public let continuation: DatabaseBytes?
        public let snapshotVersion: Int64?

        public init(
            triples: [DatabaseRDFQuad],
            continuation: DatabaseBytes? = nil,
            snapshotVersion: Int64? = nil
        ) {
            self.triples = triples
            self.continuation = continuation
            self.snapshotVersion = snapshotVersion
        }

        fileprivate func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try writer.writeCount(triples.count)
            for triple in triples { try triple.encode(into: &writer) }
            try writer.writeOptionalBytes(continuation)
            writer.writeBool(snapshotVersion != nil)
            if let snapshotVersion { writer.writeInt64(snapshotVersion) }
        }

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let count = try reader.readCount()
            var triples: [DatabaseRDFQuad] = []
            triples.reserveCapacity(count)
            for _ in 0..<count { triples.append(try DatabaseRDFQuad(from: &reader)) }
            let continuation = try reader.readOptionalBytes()
            self.init(
                triples: triples,
                continuation: continuation,
                snapshotVersion: try reader.readBool() ? try reader.readInt64() : nil
            )
        }
    }

    public enum Response: DatabaseWireValue, Hashable {
        case rows(RowPage)
        case boolean(Bool)
        case rdfGraph(GraphPage)

        public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            switch self {
            case .rows(let page):
                writer.writeUInt8(1)
                try page.encode(into: &writer)
            case .boolean(let value):
                writer.writeUInt8(2)
                writer.writeBool(value)
            case .rdfGraph(let page):
                writer.writeUInt8(3)
                try page.encode(into: &writer)
            }
        }

        public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1: self = .rows(try RowPage(from: &reader))
            case 2: self = .boolean(try reader.readBool())
            case 3: self = .rdfGraph(try GraphPage(from: &reader))
            case let tag: throw .invalidResultPayload(tag)
            }
        }
    }
}
