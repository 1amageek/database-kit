import DatabaseTypes
import DatabaseValue
import QueryIR

extension QueryIRWireCodec {
    static func encodeDataSource(
        _ source: DataSource,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try QueryIRExpressionWireEncoder.encode(source, into: &writer)
    }

    static func decodeDataSource(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DataSource {
        try QueryIRExpressionWireDecoder.decodeDataSource(from: &reader)
    }

    static func encodeTableRef(
        _ table: TableRef,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeOptionalString(table.schema, into: &writer)
        try writer.writeString(table.table)
        try writeOptionalString(table.alias, into: &writer)
        try table.partitions.encode(into: &writer)
    }

    static func decodeTableRef(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> TableRef {
        let schema = try readOptionalString(from: &reader)
        let table = try reader.readString()
        let alias = try readOptionalString(from: &reader)
        return TableRef(
            schema: schema,
            table: table,
            alias: alias,
            partitions: try FieldObject(from: &reader)
        )
    }

    static func encodeGraphPattern(
        _ pattern: GraphPattern,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try QueryIRExpressionWireEncoder.encode(pattern, into: &writer)
    }

    static func decodeGraphPattern(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> GraphPattern {
        try QueryIRExpressionWireDecoder.decodeGraphPattern(from: &reader)
    }

    static func encodeSPARQLTerm(
        _ term: SPARQLTerm,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try QueryIRSPARQLTermWireCodec.encode(term, into: &writer)
    }

    static func decodeSPARQLTerm(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SPARQLTerm {
        try QueryIRSPARQLTermWireCodec.decode(from: &reader)
    }

    static func encodePropertyPath(
        _ path: PropertyPath,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try QueryIRPropertyPathWireCodec.encode(path, into: &writer)
    }

    static func decodePropertyPath(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> PropertyPath {
        try QueryIRPropertyPathWireCodec.decode(from: &reader)
    }

    private static func encodeJoinClause(
        _ join: JoinClause,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt8(joinTypeTag(join.type))
        try encodeDataSource(join.left, into: &writer)
        try encodeDataSource(join.right, into: &writer)
        try writeOptional(join.condition, into: &writer) {
            (condition: JoinCondition, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            switch condition {
            case .on(let expression):
                writer.writeUInt8(0)
                try encodeExpression(expression, into: &writer)
            case .using(let columns):
                writer.writeUInt8(1)
                try writeStrings(columns, into: &writer)
            }
        }
    }

    private static func decodeJoinClause(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> JoinClause {
        let type = try joinType(from: &reader)
        let left = try decodeDataSource(from: &reader)
        let right = try decodeDataSource(from: &reader)
        let condition: JoinCondition? = try readOptional(from: &reader) {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> JoinCondition in
            switch try reader.readUInt8() {
            case 0: return .on(try decodeExpression(from: &reader))
            case 1: return .using(try readStrings(from: &reader))
            case let tag: throw .invalidValueTag(tag)
            }
        }
        return JoinClause(type: type, left: left, right: right, condition: condition)
    }

    private static func joinTypeTag(_ type: JoinType) -> UInt8 {
        switch type {
        case .inner: return 0
        case .left: return 1
        case .right: return 2
        case .full: return 3
        case .cross: return 4
        case .natural: return 5
        case .naturalLeft: return 6
        case .naturalRight: return 7
        case .naturalFull: return 8
        case .lateral: return 9
        case .leftLateral: return 10
        }
    }

    private static func joinType(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> JoinType {
        switch try reader.readUInt8() {
        case 0: return .inner
        case 1: return .left
        case 2: return .right
        case 3: return .full
        case 4: return .cross
        case 5: return .natural
        case 6: return .naturalLeft
        case 7: return .naturalRight
        case 8: return .naturalFull
        case 9: return .lateral
        case 10: return .leftLateral
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeGraphTableSource(
        _ source: GraphTableSource,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(source.graphName)
        try encodeMatchPattern(source.matchPattern, into: &writer)
        try writeOptional(source.columns, into: &writer) {
            (columns: [GraphTableColumn], writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writeArray(columns, into: &writer) {
                (column: GraphTableColumn, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try encodeExpression(column.expression, into: &writer)
                try writer.writeString(column.alias)
            }
        }
        try writeOptional(source.alias, into: &writer) {
            (alias: String, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writer.writeString(alias)
        }
    }

    private static func decodeGraphTableSource(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> GraphTableSource {
        GraphTableSource(
            graphName: try reader.readString(),
            matchPattern: try decodeMatchPattern(from: &reader),
            columns: try readOptional(from: &reader) {
                (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [GraphTableColumn] in
                try readArray(from: &reader) {
                    (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> GraphTableColumn in
                    GraphTableColumn(
                        expression: try decodeExpression(from: &reader),
                        alias: try reader.readString()
                    )
                }
            },
            alias: try readOptional(from: &reader) {
                (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> String in
                try reader.readString()
            }
        )
    }

    private static func encodeMatchPattern(
        _ pattern: MatchPattern,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeArray(pattern.paths, into: &writer, encode: encodePathPattern)
        try writeOptional(pattern.where, into: &writer, encode: encodeExpression)
    }

    private static func decodeMatchPattern(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> MatchPattern {
        MatchPattern(
            paths: try readArray(from: &reader, decode: decodePathPattern),
            where: try readOptional(from: &reader, decode: decodeExpression)
        )
    }

    private static func encodePathPattern(
        _ pattern: PathPattern,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeOptionalString(pattern.pathVariable, into: &writer)
        try writeArray(pattern.elements, into: &writer, encode: encodePathElement)
        try writeOptional(pattern.mode, into: &writer, encode: encodePathMode)
    }

    private static func decodePathPattern(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> PathPattern {
        PathPattern(
            pathVariable: try readOptionalString(from: &reader),
            elements: try readArray(from: &reader, decode: decodePathElement),
            mode: try readOptional(from: &reader, decode: decodePathMode)
        )
    }

    private static func encodePathElement(
        _ element: PathElement,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch element {
        case .node(let node):
            writer.writeUInt8(0)
            try encodeNodePattern(node, into: &writer)
        case .edge(let edge):
            writer.writeUInt8(1)
            try encodeEdgePattern(edge, into: &writer)
        case .quantified(let pattern, let quantifier):
            writer.writeUInt8(2)
            try encodePathPattern(pattern, into: &writer)
            try encodePathQuantifier(quantifier, into: &writer)
        case .alternation(let patterns):
            writer.writeUInt8(3)
            try writeArray(patterns, into: &writer, encode: encodePathPattern)
        }
    }

    private static func decodePathElement(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> PathElement {
        switch try reader.readUInt8() {
        case 0: return .node(try decodeNodePattern(from: &reader))
        case 1: return .edge(try decodeEdgePattern(from: &reader))
        case 2:
            return .quantified(
                try decodePathPattern(from: &reader),
                quantifier: try decodePathQuantifier(from: &reader)
            )
        case 3: return .alternation(try readArray(from: &reader, decode: decodePathPattern))
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeNodePattern(
        _ node: NodePattern,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeOptionalString(node.variable, into: &writer)
        try writeOptionalStrings(node.labels, into: &writer)
        try writeOptional(node.properties, into: &writer) {
            (properties: [PropertyBinding], writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writeArray(properties, into: &writer, encode: encodePropertyBinding)
        }
    }

    private static func decodeNodePattern(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> NodePattern {
        NodePattern(
            variable: try readOptionalString(from: &reader),
            labels: try readOptionalStrings(from: &reader),
            properties: try readOptional(from: &reader) {
                (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [PropertyBinding] in
                try readArray(from: &reader, decode: decodePropertyBinding)
            }
        )
    }

    private static func encodeEdgePattern(
        _ edge: EdgePattern,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeOptionalString(edge.variable, into: &writer)
        try writeOptionalStrings(edge.labels, into: &writer)
        try writeOptional(edge.properties, into: &writer) {
            (properties: [PropertyBinding], writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writeArray(properties, into: &writer, encode: encodePropertyBinding)
        }
        writer.writeUInt8(edgeDirectionTag(edge.direction))
    }

    private static func decodeEdgePattern(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> EdgePattern {
        EdgePattern(
            variable: try readOptionalString(from: &reader),
            labels: try readOptionalStrings(from: &reader),
            properties: try readOptional(from: &reader) {
                (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [PropertyBinding] in
                try readArray(from: &reader, decode: decodePropertyBinding)
            },
            direction: try decodeEdgeDirection(from: &reader)
        )
    }

    private static func encodePropertyBinding(
        _ binding: PropertyBinding,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(binding.key)
        try encodeExpression(binding.value, into: &writer)
    }

    private static func decodePropertyBinding(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> PropertyBinding {
        PropertyBinding(
            key: try reader.readString(),
            value: try decodeExpression(from: &reader)
        )
    }

    private static func encodePathQuantifier(
        _ quantifier: PathQuantifier,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch quantifier {
        case .exactly(let count):
            writer.writeUInt8(0)
            try writeInt(count, into: &writer)
        case .range(let minimum, let maximum):
            writer.writeUInt8(1)
            try writeOptionalInt(minimum, into: &writer)
            try writeOptionalInt(maximum, into: &writer)
        case .zeroOrMore: writer.writeUInt8(2)
        case .oneOrMore: writer.writeUInt8(3)
        case .zeroOrOne: writer.writeUInt8(4)
        }
    }

    private static func decodePathQuantifier(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> PathQuantifier {
        switch try reader.readUInt8() {
        case 0: return .exactly(try readInt(from: &reader))
        case 1:
            return .range(
                min: try readOptionalInt(from: &reader),
                max: try readOptionalInt(from: &reader)
            )
        case 2: return .zeroOrMore
        case 3: return .oneOrMore
        case 4: return .zeroOrOne
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodePathMode(
        _ mode: PathMode,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch mode {
        case .walk: writer.writeUInt8(0)
        case .trail: writer.writeUInt8(1)
        case .acyclic: writer.writeUInt8(2)
        case .simple: writer.writeUInt8(3)
        case .anyShortest: writer.writeUInt8(4)
        case .allShortest: writer.writeUInt8(5)
        case .shortestK(let count):
            writer.writeUInt8(6)
            try writeInt(count, into: &writer)
        }
    }

    private static func decodePathMode(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> PathMode {
        switch try reader.readUInt8() {
        case 0: return .walk
        case 1: return .trail
        case 2: return .acyclic
        case 3: return .simple
        case 4: return .anyShortest
        case 5: return .allShortest
        case 6: return .shortestK(try readInt(from: &reader))
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func edgeDirectionTag(_ direction: EdgeDirection) -> UInt8 {
        switch direction {
        case .outgoing: return 0
        case .incoming: return 1
        case .undirected: return 2
        case .any: return 3
        }
    }

    private static func decodeEdgeDirection(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> EdgeDirection {
        switch try reader.readUInt8() {
        case 0: return .outgoing
        case 1: return .incoming
        case 2: return .undirected
        case 3: return .any
        case let tag: throw .invalidValueTag(tag)
        }
    }

    static func encodeTriplePattern(
        _ triple: TriplePattern,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeSPARQLTerm(triple.subject, into: &writer)
        try encodeSPARQLTerm(triple.predicate, into: &writer)
        try encodeSPARQLTerm(triple.object, into: &writer)
    }

    static func decodeTriplePattern(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> TriplePattern {
        TriplePattern(
            subject: try decodeSPARQLTerm(from: &reader),
            predicate: try decodeSPARQLTerm(from: &reader),
            object: try decodeSPARQLTerm(from: &reader)
        )
    }

    private static func encodeAggregateBinding(
        _ binding: AggregateBinding,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeSPARQLVariableName(binding.variable, into: &writer)
        try encodeAggregate(binding.aggregate, into: &writer)
    }

    private static func decodeAggregateBinding(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> AggregateBinding {
        AggregateBinding(
            variable: try readSPARQLVariableName(from: &reader),
            aggregate: try decodeAggregate(from: &reader)
        )
    }

    private static func encodeBinaryGraphPattern(
        tag: UInt8,
        lhs: GraphPattern,
        rhs: GraphPattern,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt8(tag)
        try encodeGraphPattern(lhs, into: &writer)
        try encodeGraphPattern(rhs, into: &writer)
    }

    private static func decodeBinaryGraphPattern(
        from reader: inout DatabaseWireReader,
        build: (GraphPattern, GraphPattern) -> GraphPattern
    ) throws(DatabaseWireError) -> GraphPattern {
        let lhs = try decodeGraphPattern(from: &reader)
        let rhs = try decodeGraphPattern(from: &reader)
        return build(lhs, rhs)
    }

}
