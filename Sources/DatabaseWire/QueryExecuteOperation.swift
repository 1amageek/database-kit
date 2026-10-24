import DatabaseTypes
import DatabaseKit

public enum QueryExecuteOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.queryExecute

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
        public let input: QueryInput
        public let parameters: [QueryParameter]
        public let graphPartitions: FieldObject
        public let page: Page?
        public let budget: ExecutionBudget

        public init(
            input: QueryInput,
            parameters: [QueryParameter] = [],
            graphPartitions: FieldObject = FieldObject(),
            page: Page? = nil,
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
            try QueryIRWireFormat.writeOptional(page, into: &writer) {
                (page: Page, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try page.encode(into: &writer)
            }
            try budget.encode(into: &writer)
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            try reader.admitQueryRootRetention()
            let input = try QueryInput(from: &reader)
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
                page: try QueryIRWireFormat.readOptional(from: &reader) {
                    (reader: inout DatabaseWireReader) throws(DatabaseWireError) in try Page(from: &reader)
                },
                budget: try ExecutionBudget(from: &reader)
            )
        }
    }

    #if DATABASE_KIT_MULTI_BASE
    public typealias Response = QueryResult<QueryRowPage, RDFGraphPage, QueryBooleanResult>
    #else
    public typealias Response = QueryResult<QueryRowPage, RDFGraphPage, Bool>
    #endif
}
