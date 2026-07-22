import QueryIR

extension QueryIRWireCodec {
    static func encodeExpression(
        _ expression: Expression,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try QueryIRExpressionWireEncoder.encode(expression, into: &writer)
    }

    static func decodeExpression(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Expression {
        try QueryIRExpressionWireDecoder.decode(from: &reader)
    }

    static func encodeAggregate(
        _ aggregate: AggregateFunction,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch aggregate {
        case .count(let expression, let distinct):
            writer.writeUInt8(0)
            try writeOptional(expression, into: &writer, encode: encodeExpression)
            writer.writeBool(distinct)
        case .sum(let expression, let distinct):
            writer.writeUInt8(1)
            try encodeExpression(expression, into: &writer)
            writer.writeBool(distinct)
        case .avg(let expression, let distinct):
            writer.writeUInt8(2)
            try encodeExpression(expression, into: &writer)
            writer.writeBool(distinct)
        case .min(let expression):
            writer.writeUInt8(3)
            try encodeExpression(expression, into: &writer)
        case .max(let expression):
            writer.writeUInt8(4)
            try encodeExpression(expression, into: &writer)
        case .groupConcat(let expression, let separator, let distinct):
            writer.writeUInt8(5)
            try encodeExpression(expression, into: &writer)
            try writeOptionalString(separator, into: &writer)
            writer.writeBool(distinct)
        case .sample(let expression):
            writer.writeUInt8(6)
            try encodeExpression(expression, into: &writer)
        case .arrayAgg(let expression, let orderBy, let distinct):
            writer.writeUInt8(7)
            try encodeExpression(expression, into: &writer)
            try writeOptional(orderBy, into: &writer) {
                (keys: [SortKey], writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try writeArray(keys, into: &writer, encode: encodeSortKey)
            }
            writer.writeBool(distinct)
        }
    }

    static func decodeAggregate(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> AggregateFunction {
        switch try reader.readUInt8() {
        case 0:
            return .count(
                try readOptional(from: &reader, decode: decodeExpression),
                distinct: try reader.readBool()
            )
        case 1:
            return .sum(try decodeExpression(from: &reader), distinct: try reader.readBool())
        case 2:
            return .avg(try decodeExpression(from: &reader), distinct: try reader.readBool())
        case 3: return .min(try decodeExpression(from: &reader))
        case 4: return .max(try decodeExpression(from: &reader))
        case 5:
            return .groupConcat(
                try decodeExpression(from: &reader),
                separator: try readOptionalString(from: &reader),
                distinct: try reader.readBool()
            )
        case 6: return .sample(try decodeExpression(from: &reader))
        case 7:
            return .arrayAgg(
                try decodeExpression(from: &reader),
                orderBy: try readOptional(from: &reader) {
                    (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [SortKey] in
                    try readArray(from: &reader, decode: decodeSortKey)
                },
                distinct: try reader.readBool()
            )
        case let tag: throw .invalidValueTag(tag)
        }
    }

    static func encodeSortKey(
        _ key: SortKey,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeExpression(key.expression, into: &writer)
        writer.writeUInt8(key.direction == .ascending ? 0 : 1)
        try writeOptional(key.nulls, into: &writer) { value, writer in
            writer.writeUInt8(value == .first ? 0 : 1)
        }
    }

    static func decodeSortKey(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SortKey {
        let expression = try decodeExpression(from: &reader)
        let directionTag = try reader.readUInt8()
        guard directionTag <= 1 else { throw .invalidValueTag(directionTag) }
        let nulls: NullOrdering? = try readOptional(from: &reader) {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> NullOrdering in
            let tag = try reader.readUInt8()
            guard tag <= 1 else { throw .invalidValueTag(tag) }
            return tag == 0 ? .first : .last
        }
        return SortKey(
            expression,
            direction: directionTag == 0 ? .ascending : .descending,
            nulls: nulls
        )
    }

    static func encodeCaseWhenPair(
        _ pair: CaseWhenPair,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeExpression(pair.condition, into: &writer)
        try encodeExpression(pair.result, into: &writer)
    }

    static func decodeCaseWhenPair(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> CaseWhenPair {
        CaseWhenPair(
            condition: try decodeExpression(from: &reader),
            result: try decodeExpression(from: &reader)
        )
    }

    static func encodeDataType(
        _ type: DataType,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try QueryIRDataTypeWireCodec.encode(type, into: &writer)
    }

    static func decodeDataType(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DataType {
        try QueryIRDataTypeWireCodec.decode(from: &reader)
    }

    private static func encodeUnaryExpression(
        tag: UInt8,
        value: Expression,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt8(tag)
        try encodeExpression(value, into: &writer)
    }

    private static func encodeBinaryExpression(
        tag: UInt8,
        lhs: Expression,
        rhs: Expression,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt8(tag)
        try encodeExpression(lhs, into: &writer)
        try encodeExpression(rhs, into: &writer)
    }

    private static func decodeBinaryExpression(
        from reader: inout DatabaseWireReader,
        build: (Expression, Expression) -> Expression
    ) throws(DatabaseWireError) -> Expression {
        let lhs = try decodeExpression(from: &reader)
        let rhs = try decodeExpression(from: &reader)
        return build(lhs, rhs)
    }
}
