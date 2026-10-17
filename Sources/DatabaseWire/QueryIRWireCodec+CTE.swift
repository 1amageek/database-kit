import DatabaseKit

extension QueryIRWireFormat {
    static func encodeCTEMetadata(
        _ subquery: NamedSubquery,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeOptional(subquery.search, into: &writer) {
            (search: CTESearchClause, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writer.writeUInt8(search.order == .depthFirst ? 0 : 1)
            try writeArray(search.columns, into: &writer) {
                (value: String, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try writer.writeString(value)
            }
            try writer.writeString(search.sequenceColumn)
        }
        try writeOptional(subquery.cycle, into: &writer) {
            (cycle: CTECycleClause, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writeArray(cycle.columns, into: &writer) {
                (value: String, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try writer.writeString(value)
            }
            try writer.writeString(cycle.markColumn)
            try writer.writeString(cycle.pathColumn)
            switch (cycle.markValue, cycle.defaultValue) {
            case (.some(let mark), .some(let defaultValue)):
                writer.writeBool(true)
                try encodeLiteral(mark, into: &writer)
                try encodeLiteral(defaultValue, into: &writer)
            case (nil, nil):
                writer.writeBool(false)
            default:
                throw .invalidQueryStructure(.invalidCTECycleClause)
            }
        }
    }

    static func decodeCTEMetadata(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> (search: CTESearchClause?, cycle: CTECycleClause?) {
        let search: CTESearchClause? = try readOptional(from: &reader) {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> CTESearchClause in
            let order: CTESearchOrder
            switch try reader.readUInt8() {
            case 0: order = .depthFirst
            case 1: order = .breadthFirst
            case let tag: throw .invalidValueTag(tag)
            }
            return CTESearchClause(order: order,
                columns: try readArray(from: &reader) {
                    (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> String in
                    try reader.readString()
                },
                sequenceColumn: try reader.readString())
        }
        let cycle: CTECycleClause? = try readOptional(from: &reader) {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> CTECycleClause in
            let columns = try readArray(from: &reader) {
                (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> String in
                try reader.readString()
            }
            let markColumn = try reader.readString()
            let pathColumn = try reader.readString()
            let hasConstants = try reader.readBool()
            let markValue = hasConstants ? try decodeLiteral(from: &reader) : nil
            let defaultValue = hasConstants ? try decodeLiteral(from: &reader) : nil
            return CTECycleClause(columns: columns, markColumn: markColumn, pathColumn: pathColumn,
                markValue: markValue, defaultValue: defaultValue)
        }
        return (search, cycle)
    }
}
