import DatabaseTypes
import DatabaseKit

extension QueryIRWireFormat {
    static func encodeSelectQuery(
        _ query: SelectQuery,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try QueryIRExpressionWireEncoder.encode(query, into: &writer)
    }

    static func decodeSelectQuery(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SelectQuery {
        try QueryIRExpressionWireDecoder.decodeSelect(from: &reader)
    }

    static func encodeAccessPath(
        _ path: AccessPath,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch path {
        case .index(let source):
            writer.writeUInt8(0)
            try encodeIndexScanSource(source, into: &writer)
        case .fusion(let source):
            writer.writeUInt8(1)
            try writeArray(source.inputs, into: &writer, encode: encodeIndexScanSource)
            try writer.writeString(source.strategyIdentifier)
            try encodeParameters(source.parameters, into: &writer)
            try writer.writeString(source.identityField)
        }
    }

    static func decodeAccessPath(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> AccessPath {
        switch try reader.readUInt8() {
        case 0:
            return .index(try decodeIndexScanSource(from: &reader))
        case 1:
            return .fusion(
                FusionSource(
                    inputs: try readArray(from: &reader, decode: decodeIndexScanSource),
                    strategyIdentifier: try reader.readString(),
                    parameters: try decodeParameters(from: &reader),
                    identityField: try reader.readString()
                )
            )
        case let tag:
            throw .invalidValueTag(tag)
        }
    }

    static func encodeProjection(
        _ projection: Projection,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch projection {
        case .all:
            writer.writeUInt8(0)
        case .allFrom(let source):
            writer.writeUInt8(1)
            try writer.writeString(source)
        case .items(let items):
            writer.writeUInt8(2)
            try writeArray(items, into: &writer, encode: encodeProjectionItem)
        case .distinctItems(let items):
            writer.writeUInt8(3)
            try writeArray(items, into: &writer, encode: encodeProjectionItem)
        }
    }

    static func decodeProjection(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Projection {
        switch try reader.readUInt8() {
        case 0: return .all
        case 1: return .allFrom(try reader.readString())
        case 2: return .items(try readArray(from: &reader, decode: decodeProjectionItem))
        case 3:
            return .distinctItems(try readArray(from: &reader, decode: decodeProjectionItem))
        case let tag: throw .invalidValueTag(tag)
        }
    }

    static func encodeProjectionItem(
        _ projectionItem: ProjectionItem,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeExpression(projectionItem.expression, into: &writer)
        try writeOptionalString(projectionItem.alias, into: &writer)
    }

    static func decodeProjectionItem(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> ProjectionItem {
        ProjectionItem(
            try decodeExpression(from: &reader),
            alias: try readOptionalString(from: &reader)
        )
    }

    static func encodeNamedSubquery(
        _ subquery: NamedSubquery,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(subquery.name)
        try writeOptionalStrings(subquery.columns, into: &writer)
        try encodeSelectQuery(subquery.query, into: &writer)
        try writeOptional(subquery.materialized, into: &writer) { value, writer in
            writer.writeUInt8(value == .materialized ? 0 : 1)
        }
    }

    static func decodeNamedSubquery(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> NamedSubquery {
        let name = try reader.readString()
        let columns = try readOptionalStrings(from: &reader)
        let query = try decodeSelectQuery(from: &reader)
        let materialized: Materialization? = try readOptional(from: &reader) {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> Materialization in
            let tag = try reader.readUInt8()
            guard tag <= 1 else { throw .invalidValueTag(tag) }
            return tag == 0 ? .materialized : .notMaterialized
        }
        return NamedSubquery(
            name: name,
            columns: columns,
            query: query,
            materialized: materialized
        )
    }

    private static func encodeIndexScanSource(
        _ source: IndexScanSource,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(source.indexName)
        try writer.writeString(source.kindIdentifier)
        try encodeParameters(source.parameters, into: &writer)
    }

    private static func decodeIndexScanSource(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> IndexScanSource {
        IndexScanSource(
            indexName: try reader.readString(),
            kindIdentifier: try reader.readString(),
            parameters: try decodeParameters(from: &reader)
        )
    }

    private static func encodeParameters(
        _ parameters: [String: FieldValue],
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        // Canonical ordering requires one sorted entry view because Dictionary
        // does not expose ordered borrowed iteration.
        let entries = parameters.sorted { $0.key < $1.key }
        try writer.writeCount(entries.count)
        for (key, value) in entries {
            try writer.writeString(key)
            try value.encode(into: &writer)
        }
    }

    private static func decodeParameters(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> [String: FieldValue] {
        let count = try reader.readCount()
        var parameters: [String: FieldValue] = [:]
        parameters.reserveCapacity(count)
        var previousKey: String?
        for _ in 0..<count {
            let key = try reader.readString()
            if let previousKey, key <= previousKey {
                throw .nonCanonicalQueryParameterMap
            }
            parameters[key] = try FieldValue(from: &reader)
            previousKey = key
        }
        return parameters
    }
}
