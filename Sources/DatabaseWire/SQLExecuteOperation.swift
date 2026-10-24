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

    // Deprecated during EIR24 migration; the unified query operation replaces this descriptor.
    public typealias Response = QueryExecuteOperation.Response
}
