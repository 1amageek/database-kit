import DatabaseTypes
import DatabaseKit

extension QueryInput {
    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        switch self {
        case .text(let language, let statement):
            writer.writeUInt8(1)
            writer.writeUInt8(language.rawValue)
            try writer.writeString(statement)
        case .statement(let statement):
            writer.writeUInt8(2)
            try QueryIRWireFormat.encodeStatement(statement, into: &writer)
        case .block(let block):
            writer.writeUInt8(3)
            try QueryIRWireFormat.encodeBlock(block, into: &writer)
        }
    }

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        switch try reader.readUInt8() {
        case 1:
            let raw = try reader.readUInt8()
            guard let language = QueryLanguage(rawValue: raw) else {
                throw .invalidQueryLanguage(raw)
            }
            self = .text(language: language, statement: try reader.readString())
        case 2:
            self = .statement(try QueryIRWireFormat.decodeStatement(from: &reader))
        case 3:
            self = .block(try QueryIRWireFormat.decodeBlock(from: &reader))
        case let tag: throw .invalidQueryInput(tag)
        }
    }
}
