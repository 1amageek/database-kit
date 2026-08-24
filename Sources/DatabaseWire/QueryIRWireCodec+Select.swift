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
            try writeArray(source.stages, into: &writer, encode: encodeFusionStage)
            try encodeFusionStrategy(source.strategy, into: &writer)
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
                    stages: try readArray(from: &reader, decode: decodeFusionStage),
                    strategy: try decodeFusionStrategy(from: &reader)
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
        try IndexTypeWireCodec.encode(source.indexType, into: &writer)
        try encodeParameters(source.parameters, into: &writer)
    }

    private static func decodeIndexScanSource(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> IndexScanSource {
        IndexScanSource(
            indexName: try reader.readString(),
            indexType: try IndexTypeWireCodec.decode(from: &reader),
            parameters: try decodeParameters(from: &reader)
        )
    }

    private static func encodeFusionStage(
        _ stage: FusionStageSource,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeArray(stage.inputs, into: &writer, encode: encodeFusionInput)
    }

    private static func decodeFusionStage(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> FusionStageSource {
        FusionStageSource(
            inputs: try readArray(from: &reader, decode: decodeFusionInput)
        )
    }

    private static func encodeFusionInput(
        _ input: FusionInput,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeFusionOperation(input.operation, into: &writer)
        try writeOptional(input.scoring, into: &writer, encode: encodeFusionScoring)
        writer.writeUInt8(input.requirement.rawValue)
        writeOptionalUInt64(input.limit, into: &writer)
    }

    private static func decodeFusionInput(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> FusionInput {
        let operation = try decodeFusionOperation(from: &reader)
        let scoring = try readOptional(from: &reader, decode: decodeFusionScoring)
        let requirementTag = try reader.readUInt8()
        guard let requirement = FusionInputRequirement(rawValue: requirementTag) else {
            throw .invalidValueTag(requirementTag)
        }
        return FusionInput(
            operation: operation,
            scoring: scoring,
            requirement: requirement,
            limit: try readOptionalUInt64(from: &reader)
        )
    }

    private static func encodeFusionOperation(
        _ operation: FusionInputOperation,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch operation {
        case .index(let source):
            writer.writeUInt8(0)
            try encodeFusionIndexSource(source, into: &writer)
        case .connected(let source):
            writer.writeUInt8(3)
            try encodeFusionConnectedSource(source, into: &writer)
        case .filter(let expression):
            writer.writeUInt8(1)
            try encodeExpression(expression, into: &writer)
        case .order(let keys):
            writer.writeUInt8(2)
            try writeArray(keys, into: &writer, encode: encodeSortKey)
        }
    }

    private static func decodeFusionOperation(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> FusionInputOperation {
        switch try reader.readUInt8() {
        case 0:
            return .index(try decodeFusionIndexSource(from: &reader))
        case 1:
            return .filter(try decodeExpression(from: &reader))
        case 2:
            return .order(try readArray(from: &reader, decode: decodeSortKey))
        case 3:
            return .connected(
                try decodeFusionConnectedSource(from: &reader)
            )
        case let tag:
            throw .invalidValueTag(tag)
        }
    }

    private static func encodeFusionIndexSource(
        _ source: FusionIndexSource,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeFusionIndexSelection(source.selection, into: &writer)
        try writeArray(source.referencedFields, into: &writer) {
            (identity: FieldIdentity, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writer.writeString(identity.name)
            try writeInt(identity.number, into: &writer)
        }
        try encodeParameters(source.parameters, into: &writer)
    }

    private static func encodeFusionIndexSelection(
        _ selection: FusionIndexSelection,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch selection {
        case .named(let name, let type):
            writer.writeUInt8(0)
            try writer.writeString(name)
            try IndexTypeWireCodec.encode(type, into: &writer)
        case .matching(let type, let fields, let fieldMatch):
            writer.writeUInt8(1)
            try IndexTypeWireCodec.encode(type, into: &writer)
            try writeArray(fields, into: &writer) {
                (identity: FieldIdentity, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try writer.writeString(identity.name)
                try writeInt(identity.number, into: &writer)
            }
            writer.writeUInt8(fieldMatch.rawValue)
        }
    }

    private static func decodeFusionIndexSource(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> FusionIndexSource {
        let selection = try decodeFusionIndexSelection(from: &reader)
        let referencedFields: [FieldIdentity] = try readArray(from: &reader) {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> FieldIdentity in
            FieldIdentity(
                name: try reader.readString(),
                number: try readInt(from: &reader)
            )
        }
        return FusionIndexSource(
            selection: selection,
            referencedFields: referencedFields,
            parameters: try decodeParameters(from: &reader)
        )
    }

    private static func decodeFusionIndexSelection(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> FusionIndexSelection {
        switch try reader.readUInt8() {
        case 0:
            return .named(
                name: try reader.readString(),
                type: try IndexTypeWireCodec.decode(from: &reader)
            )
        case 1:
            let type = try IndexTypeWireCodec.decode(from: &reader)
            let fields: [FieldIdentity] = try readArray(from: &reader) {
                (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> FieldIdentity in
                FieldIdentity(
                    name: try reader.readString(),
                    number: try readInt(from: &reader)
                )
            }
            let tag = try reader.readUInt8()
            guard let fieldMatch = FusionIndexFieldMatch(rawValue: tag) else {
                throw .invalidValueTag(tag)
            }
            return .matching(
                type: type,
                fields: fields,
                fieldMatch: fieldMatch
            )
        case let tag:
            throw .invalidValueTag(tag)
        }
    }

    private static func encodeFusionConnectedSource(
        _ source: FusionConnectedSource,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(source.edgeEntity)
        try source.edgePartitions.encode(into: &writer)
        try encodeFusionIndexSelection(source.selection, into: &writer)
        try writer.writeString(source.resultField.name)
        try writeInt(source.resultField.number, into: &writer)
        try writer.writeString(source.origin)
        try writeOptionalString(source.edgeLabel, into: &writer)
        writer.writeUInt8(source.direction.rawValue)
        writer.writeUInt64(source.maximumHops)
    }

    private static func decodeFusionConnectedSource(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> FusionConnectedSource {
        let edgeEntity = try reader.readString()
        let edgePartitions = try FieldObject(from: &reader)
        let selection = try decodeFusionIndexSelection(from: &reader)
        let resultField = FieldIdentity(
            name: try reader.readString(),
            number: try readInt(from: &reader)
        )
        let origin = try reader.readString()
        let edgeLabel = try readOptionalString(from: &reader)
        let directionTag = try reader.readUInt8()
        guard let direction = FusionConnectedDirection(
            rawValue: directionTag
        ) else {
            throw .invalidValueTag(directionTag)
        }
        return FusionConnectedSource(
            edgeEntity: edgeEntity,
            edgePartitions: edgePartitions,
            selection: selection,
            resultField: resultField,
            origin: origin,
            edgeLabel: edgeLabel,
            direction: direction,
            maximumHops: try reader.readUInt64()
        )
    }

    private static func encodeFusionScoring(
        _ scoring: FusionScoring,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch scoring {
        case .position:
            writer.writeUInt8(0)
        case .annotation(let name, let order):
            writer.writeUInt8(1)
            try writer.writeString(name)
            writer.writeUInt8(order.rawValue)
        }
    }

    private static func decodeFusionScoring(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> FusionScoring {
        switch try reader.readUInt8() {
        case 0:
            return .position
        case 1:
            let name = try reader.readString()
            let tag = try reader.readUInt8()
            guard let order = FusionScoreOrder(rawValue: tag) else {
                throw .invalidValueTag(tag)
            }
            return .annotation(name: name, order: order)
        case let tag:
            throw .invalidValueTag(tag)
        }
    }

    private static func encodeFusionStrategy(
        _ strategy: FusionStrategy,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch strategy {
        case .reciprocalRank(let rankConstant):
            writer.writeUInt8(0)
            writer.writeUInt64(rankConstant)
        case .sum:
            writer.writeUInt8(1)
        case .maximum:
            writer.writeUInt8(2)
        case .weighted(let weights):
            writer.writeUInt8(3)
            try writer.writeCount(weights.count)
            for weight in weights {
                writer.writeDouble(weight)
            }
        }
    }

    private static func decodeFusionStrategy(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> FusionStrategy {
        switch try reader.readUInt8() {
        case 0:
            return .reciprocalRank(rankConstant: try reader.readUInt64())
        case 1:
            return .sum
        case 2:
            return .maximum
        case 3:
            let count = try reader.readCount()
            var weights: [Double] = []
            weights.reserveCapacity(count)
            for _ in 0..<count {
                weights.append(try reader.readDouble())
            }
            return .weighted(weights)
        case let tag:
            throw .invalidValueTag(tag)
        }
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
