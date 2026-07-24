import DatabaseTypes
import QueryIR

extension QueryIRWireCodec {
    static func encodeSPARQLDataset(
        _ dataset: SPARQLDataset,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch dataset {
        case .implicit:
            writer.writeUInt8(0)
        case .explicit(let defaultGraphs, let namedGraphs):
            writer.writeUInt8(1)
            try writeSPARQLIRIs(defaultGraphs, into: &writer)
            try writeSPARQLIRIs(namedGraphs, into: &writer)
        }
    }

    static func decodeSPARQLDataset(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SPARQLDataset {
        switch try reader.readUInt8() {
        case 0:
            return .implicit
        case 1:
            return .explicit(
                defaultGraphs: try readSPARQLIRIs(from: &reader),
                namedGraphs: try readSPARQLIRIs(from: &reader)
            )
        case let tag:
            throw .invalidValueTag(tag)
        }
    }

    static func encodeSPARQLSolutionModifiers(
        _ modifiers: SPARQLSolutionModifiers,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeArray(
            modifiers.groupBy,
            into: &writer,
            encode: encodeExpression
        )
        try writeArray(
            modifiers.having,
            into: &writer,
            encode: encodeExpression
        )
        try writeArray(
            modifiers.orderBy,
            into: &writer,
            encode: encodeSortKey
        )
        try writeOptionalInt(modifiers.limit, into: &writer)
        try writeOptionalInt(modifiers.offset, into: &writer)
    }

    static func decodeSPARQLSolutionModifiers(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SPARQLSolutionModifiers {
        SPARQLSolutionModifiers(
            groupBy: try readArray(from: &reader, decode: decodeExpression),
            having: try readArray(from: &reader, decode: decodeExpression),
            orderBy: try readArray(from: &reader, decode: decodeSortKey),
            limit: try readOptionalInt(from: &reader),
            offset: try readOptionalInt(from: &reader)
        )
    }

    static func encodeDescribeSelection(
        _ selection: DescribeSelection,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch selection {
        case .all:
            writer.writeUInt8(0)
        case .resources(let first, let additional):
            writer.writeUInt8(1)
            try encodeSPARQLTerm(first, into: &writer)
            try writeArray(
                additional,
                into: &writer,
                encode: encodeSPARQLTerm
            )
        }
    }

    static func decodeDescribeSelection(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DescribeSelection {
        switch try reader.readUInt8() {
        case 0:
            return .all
        case 1:
            return .resources(
                first: try decodeSPARQLTerm(from: &reader),
                additional: try readArray(
                    from: &reader,
                    decode: decodeSPARQLTerm
                )
            )
        case let tag:
            throw .invalidValueTag(tag)
        }
    }
}
