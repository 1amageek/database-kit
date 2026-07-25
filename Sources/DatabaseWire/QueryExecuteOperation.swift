import DatabaseTypes
import DatabaseKit

public enum QueryExecuteOperation: DatabaseOperationDeclaration {
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
                try QueryIRWireFormat.encodeStatement(statement, into: &writer)
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
                self = .ir(try QueryIRWireFormat.decodeStatement(from: &reader))
            case let tag:
                throw .invalidQueryInput(tag)
            }
        }
    }

    public struct Page: WireValue, Hashable {
        public let limit: UInt32
        public let continuation: ByteString?

        public init(limit: UInt32 = 1_000, continuation: ByteString? = nil) {
            self.limit = limit
            self.continuation = continuation
        }

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            writer.writeUInt32(limit)
            try writer.writeOptionalBytes(continuation)
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            self.init(limit: try reader.readUInt32(), continuation: try reader.readOptionalBytes())
        }
    }

    public struct Request: WireValue, Hashable {
        public let input: Input
        public let parameters: [QueryParameter]
        public let graphPartitions: FieldObject
        public let page: Page
        public let budget: ExecutionBudget

        public init(
            input: Input,
            parameters: [QueryParameter] = [],
            graphPartitions: FieldObject = FieldObject(),
            page: Page = Page(),
            budget: ExecutionBudget = ExecutionBudget()
        ) {
            self.input = input
            self.parameters = parameters
            self.graphPartitions = graphPartitions
            self.page = page
            self.budget = budget
        }

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try input.encode(into: &writer)
            try writer.writeCount(parameters.count)
            for parameter in parameters { try parameter.encode(into: &writer) }
            try graphPartitions.encode(into: &writer)
            try page.encode(into: &writer)
            try budget.encode(into: &writer)
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let input = try Input(from: &reader)
            let count = try reader.readCount()
            var parameters: [QueryParameter] = []
            parameters.reserveCapacity(count)
            for _ in 0..<count {
                parameters.append(try QueryParameter(from: &reader))
            }
            self.init(
                input: input,
                parameters: parameters,
                graphPartitions: try FieldObject(from: &reader),
                page: try Page(from: &reader),
                budget: try ExecutionBudget(from: &reader)
            )
        }
    }

    public struct Column: Sendable, Hashable {
        public let number: UInt32
        public let name: String

        public init(number: UInt32, name: String) {
            self.number = number
            self.name = name
        }

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeUInt32(number)
            try writer.writeString(name)
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                number: try reader.readUInt32(),
                name: try reader.readString()
            )
        }
    }

    public struct Row: Sendable, Hashable {
        public let values: [FieldValue]
        public let annotations: FieldObject
        public let version: ByteString?

        public init(
            values: [FieldValue],
            annotations: FieldObject = FieldObject(),
            version: ByteString? = nil
        ) {
            self.values = values
            self.annotations = annotations
            self.version = version
        }

        fileprivate func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try writer.writeCount(values.count)
            for value in values { try value.encode(into: &writer) }
            try annotations.encode(into: &writer)
            try writer.writeOptionalBytes(version)
        }

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let valueCount = try reader.readCount()
            var values: [FieldValue] = []
            values.reserveCapacity(valueCount)
            for _ in 0..<valueCount {
                values.append(try FieldValue(from: &reader))
            }
            self.init(
                values: values,
                annotations: try FieldObject(from: &reader),
                version: try reader.readOptionalBytes()
            )
        }
    }

    public struct RowPage: Sendable, Hashable {
        public let columns: [Column]
        public let rows: [Row]
        public let continuation: ByteString?
        public let snapshotVersion: UInt64?

        public init(
            columns: [Column],
            rows: [Row],
            continuation: ByteString? = nil,
            snapshotVersion: UInt64? = nil
        ) {
            self.columns = columns
            self.rows = rows
            self.continuation = continuation
            self.snapshotVersion = snapshotVersion
        }

        fileprivate func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try writer.writeCount(columns.count)
            for column in columns {
                try column.encode(into: &writer)
            }
            try writer.writeCount(rows.count)
            for row in rows {
                guard row.values.count == columns.count else {
                    throw .invalidRowValueCount(
                        expected: columns.count,
                        actual: row.values.count
                    )
                }
                try row.encode(into: &writer)
            }
            try writer.writeOptionalBytes(continuation)
            if let snapshotVersion {
                writer.writeBool(true)
                writer.writeUInt64(snapshotVersion)
            } else {
                writer.writeBool(false)
            }
        }

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let columnCount = try reader.readCount()
            var columns: [Column] = []
            columns.reserveCapacity(columnCount)
            for _ in 0..<columnCount {
                columns.append(try Column(from: &reader))
            }
            let count = try reader.readCount()
            var rows: [Row] = []
            rows.reserveCapacity(count)
            for _ in 0..<count {
                let row = try Row(from: &reader)
                guard row.values.count == columnCount else {
                    throw .invalidRowValueCount(
                        expected: columnCount,
                        actual: row.values.count
                    )
                }
                rows.append(row)
            }
            let continuation = try reader.readOptionalBytes()
            let snapshotVersion = try reader.readBool() ? try reader.readUInt64() : nil
            self.init(
                columns: columns,
                rows: rows,
                continuation: continuation,
                snapshotVersion: snapshotVersion
            )
        }
    }

    public struct GraphPage: Sendable, Hashable {
        public let triples: [RDFQuad]
        public let continuation: ByteString?
        public let snapshotVersion: Int64?

        public init(
            triples: [RDFQuad],
            continuation: ByteString? = nil,
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
            var triples: [RDFQuad] = []
            triples.reserveCapacity(count)
            for _ in 0..<count { triples.append(try RDFQuad(from: &reader)) }
            let continuation = try reader.readOptionalBytes()
            self.init(
                triples: triples,
                continuation: continuation,
                snapshotVersion: try reader.readBool() ? try reader.readInt64() : nil
            )
        }
    }

    public enum Response: WireValue, Hashable {
        case rows(RowPage)
        case boolean(Bool)
        case rdfGraph(GraphPage)

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
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

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1: self = .rows(try RowPage(from: &reader))
            case 2: self = .boolean(try reader.readBool())
            case 3: self = .rdfGraph(try GraphPage(from: &reader))
            case let tag: throw .invalidResultPayload(tag)
            }
        }
    }
}
