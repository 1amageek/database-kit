import DatabaseKit
import DatabaseTypes

/// Executes one complete SQL request without paging or cross-request state.
public enum SQLExecuteOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.sqlExecute

    public enum Input: Sendable, Hashable {
        case text(String)
        case statement(QueryStatement)
        case block(SQLBlock)

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            switch self {
            case .text(let text): writer.writeUInt8(0); try writer.writeString(text)
            case .statement(let statement):
                writer.writeUInt8(1); try QueryIRWireFormat.encodeStatement(statement, into: &writer)
            case .block(let block):
                writer.writeUInt8(2); try QueryIRWireFormat.encodeBlock(block, into: &writer)
            }
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0: self = .text(try reader.readString())
            case 1: self = .statement(try QueryIRWireFormat.decodeStatement(from: &reader))
            case 2: self = .block(try QueryIRWireFormat.decodeBlock(from: &reader))
            case let tag: throw .invalidQueryInput(tag)
            }
        }
    }

    public struct Request: WireValue, Hashable {
        public let input: Input
        public let parameters: [QueryParameter]
        public let budget: ExecutionBudget

        public init(input: Input, parameters: [QueryParameter] = [],
                    budget: ExecutionBudget = ExecutionBudget()) {
            self.input = input
            self.parameters = parameters
            self.budget = budget
        }

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try input.encode(into: &writer)
            try writer.writeCount(parameters.count)
            for parameter in parameters { try parameter.encode(into: &writer) }
            try budget.encode(into: &writer)
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            try reader.admitQueryRootRetention()
            let input = try Input(from: &reader)
            let count = try reader.readCount()
            var parameters: [QueryParameter] = []
            parameters.reserveCapacity(count)
            for _ in 0..<count { parameters.append(try QueryParameter(from: &reader)) }
            self.init(input: input, parameters: parameters, budget: try ExecutionBudget(from: &reader))
        }
    }

    public enum Outcome: Sendable {
        case rows(Rows)
        case copy(bytes: ByteString, affectedRows: UInt64)
        case command(SQLCommandKind, affectedRows: UInt64?)

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            switch self {
            case .rows(let rows): writer.writeUInt8(0); try rows.encode(into: &writer)
            case .copy(let bytes, let count):
                writer.writeUInt8(1); try writer.writeBytes(bytes); writer.writeUInt64(count)
            case .command(let kind, let count):
                writer.writeUInt8(2); writer.writeUInt8(SQLCommandWireCodec.tag(kind))
                try QueryIRWireFormat.writeOptional(count, into: &writer) { count, writer in writer.writeUInt64(count) }
            }
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0: self = .rows(try Rows(from: &reader))
            case 1:
                let bytes = try reader.readBytes()
                self = .copy(bytes: bytes, affectedRows: try reader.readUInt64())
            case 2:
                let kind = try SQLCommandWireCodec.kind(try reader.readUInt8())
                let count: UInt64? = try QueryIRWireFormat.readOptional(from: &reader) {
                    (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> UInt64 in try reader.readUInt64()
                }
                self = .command(kind, affectedRows: count)
            case let tag: throw .invalidResultPayload(tag)
            }
        }
    }

    public struct Response: WireValue {
        public let results: [Outcome]

        public init(results: [Outcome]) { self.results = results }

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            guard !results.isEmpty else { throw .invalidSQLResponse }
            try writer.writeCount(results.count)
            for result in results {
                try writer.beginNestedValue()
                try result.encode(into: &writer)
                try writer.endNestedValue()
            }
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            try reader.admitQueryRootRetention()
            let count = try reader.readCount()
            guard count > 0 else { throw .invalidSQLResponse }
            var results: [Outcome] = []
            results.reserveCapacity(count)
            for _ in 0..<count {
                try reader.beginNestedValue()
                results.append(try Outcome(from: &reader))
                try reader.endNestedValue()
            }
            self.init(results: results)
        }
    }
}
