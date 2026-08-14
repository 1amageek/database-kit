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

    public enum Response: WireValue {
        case rows(QueryRowPage)
        #if DATABASE_KIT_MULTIPLE_BASES
        case boolean(QueryBooleanResult)
        #else
        case boolean(Bool)
        #endif
        case rdfGraph(RDFGraphPage)

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            switch self {
            case .rows(let page):
                writer.writeUInt8(1)
                try page.encode(into: &writer)
            case .boolean(let result):
                writer.writeUInt8(2)
                #if DATABASE_KIT_MULTIPLE_BASES
                try result.encode(into: &writer)
                #else
                writer.writeBool(result)
                #endif
            case .rdfGraph(let page):
                writer.writeUInt8(3)
                try page.encode(into: &writer)
            }
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1: self = .rows(try QueryRowPage(from: &reader))
            case 2:
                #if DATABASE_KIT_MULTIPLE_BASES
                self = .boolean(try QueryBooleanResult(from: &reader))
                #else
                self = .boolean(try reader.readBool())
                #endif
            case 3: self = .rdfGraph(try RDFGraphPage(from: &reader))
            case let tag: throw .invalidResultPayload(tag)
            }
        }
    }
}
