import DatabaseKit
import DatabaseTypes

extension QueryResult: WireValue
where Rows: WireValue, Graph: WireValue, Boolean: WireValue {
    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        switch self {
        case .rows(let rows):
            writer.writeUInt8(1)
            try rows.encode(into: &writer)
        case .boolean(let value):
            writer.writeUInt8(2)
            try value.encode(into: &writer)
        case .rdfGraph(let graph):
            writer.writeUInt8(3)
            try graph.encode(into: &writer)
        case .command(let kind, let affectedRows):
            writer.writeUInt8(4)
            writer.writeUInt8(SQLCommandWireCodec.tag(kind))
            try QueryIRWireFormat.writeOptional(affectedRows, into: &writer) { count, writer in
                writer.writeUInt64(count)
            }
        case .copy(let bytes, let affectedRows):
            writer.writeUInt8(5)
            try writer.writeBytes(bytes)
            writer.writeUInt64(affectedRows)
        case .block(let results):
            guard !results.isEmpty else { throw .invalidSQLResponse }
            writer.writeUInt8(6)
            try writer.writeCount(results.count)
            for result in results {
                if case .block = result { throw .invalidSQLResponse }
                try writer.beginNestedValue()
                try result.encode(into: &writer)
                try writer.endNestedValue()
            }
        }
    }

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        try self.init(from: &reader, permitsBlock: true)
    }

    private init(from reader: inout DatabaseWireReader, permitsBlock: Bool)
    throws(DatabaseWireError) {
        switch try reader.readUInt8() {
        case 1: self = .rows(try Rows(from: &reader))
        case 2: self = .boolean(try Boolean(from: &reader))
        case 3: self = .rdfGraph(try Graph(from: &reader))
        case 4:
            let kind = try SQLCommandWireCodec.kind(reader.readUInt8())
            let count = try QueryIRWireFormat.readOptional(from: &reader) {
                (reader: inout DatabaseWireReader) throws(DatabaseWireError) in try reader.readUInt64()
            }
            self = .command(kind, affectedRows: count)
        case 5:
            let bytes = try reader.readBytes()
            self = .copy(bytes: bytes, affectedRows: try reader.readUInt64())
        case 6:
            guard permitsBlock else { throw .invalidSQLResponse }
            let count = try reader.readCount()
            guard count > 0 else { throw .invalidSQLResponse }
            var results: [Self] = []
            results.reserveCapacity(count)
            for _ in 0..<count {
                try reader.beginNestedValue()
                results.append(try Self(from: &reader, permitsBlock: false))
                try reader.endNestedValue()
            }
            self = .block(results)
        case let tag: throw .invalidResultPayload(tag)
        }
    }
}

extension QueryRowPage: WireValue {}
extension RDFGraphPage: WireValue {}

extension Bool: WireValue {
    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        writer.writeBool(self)
    }

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self = try reader.readBool()
    }
}
