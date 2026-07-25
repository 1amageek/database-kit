import DatabaseTypes
import DatabaseKit

/// Encodes expression trees with an explicit continuation stack.
///
/// Collection cursors retain the source array and visit one element at a
/// time, keeping auxiliary memory proportional to nesting depth rather than
/// collection size.
enum QueryIRExpressionWireEncoder {
    static func encode(
        _ expression: Expression,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeTraversal(startingWith: .expression(expression), writer: &writer)
    }

    static func encode(
        _ query: SelectQuery,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeTraversal(startingWith: .select(query), writer: &writer)
    }

    static func encode(
        _ source: DataSource,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeTraversal(startingWith: .dataSource(source), writer: &writer)
    }

    static func encode(
        _ pattern: GraphPattern,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeTraversal(startingWith: .graphPattern(pattern), writer: &writer)
    }

    private static func encodeTraversal(
        startingWith initialStep: EncodingStep,
        writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        var encodingSteps: [EncodingStep] = [initialStep]
        while let encodingStep = encodingSteps.popLast() {
            try encode(encodingStep, writer: &writer, encodingSteps: &encodingSteps)
        }
    }
}

private extension QueryIRExpressionWireEncoder {
    enum EncodingStep {
        case expression(Expression)
        case endNestedValue
        case literal(Literal)
        case select(SelectQuery)
        case dataSource(DataSource)
        case graphPattern(GraphPattern)
        case dataType(DataType)
        case string(String)
        case optionalString(String?)
        case sparqlVariable(String)
        case bool(Bool)
        case byte(UInt8)
        case optionalInt(Int?)
        case optionalUInt64(UInt64?)
        case optionalAccessPath(AccessPath?)
        case projection(Projection)
        case projectionItemCursor([ProjectionItem], index: Int)
        case projectionItemTail(String?)
        case optionalExpressionArray([Expression]?)
        case optionalSortKeyArray([SortKey]?)
        case optionalNamedSubqueryArray([NamedSubquery]?)
        case namedSubqueryCursor([NamedSubquery], index: Int)
        case namedSubquery(NamedSubquery)
        case namedSubqueryTail(Materialization?)
        case sparqlDataset(SPARQLDataset)
        case dataSourceArrayCursor([DataSource], index: Int)
        case join(JoinClause)
        case joinCondition(JoinCondition?)
        case graphTable(GraphTableSource)
        case graphTableTail([GraphTableColumn]?, alias: String?)
        case optionalGraphTableColumns([GraphTableColumn]?)
        case graphTableColumnCursor([GraphTableColumn], index: Int)
        case graphTableColumnTail(String)
        case matchPattern(MatchPattern)
        case pathPattern(PathPattern)
        case pathPatternCursor([PathPattern], index: Int)
        case pathElement(PathElement)
        case pathElementCursor([PathElement], index: Int)
        case optionalPathMode(PathMode?)
        case pathQuantifier(PathQuantifier)
        case nodePattern(NodePattern)
        case edgePattern(EdgePattern)
        case optionalPropertyBindings([PropertyBinding]?)
        case propertyBindingCursor([PropertyBinding], index: Int)
        case graphPatternGroupByTail([Expression], [AggregateBinding])
        case aggregateBindingArray([AggregateBinding])
        case aggregateBindingCursor([AggregateBinding], index: Int)
        case expressionArray([Expression])
        case expressionArrayCursor([Expression], index: Int)
        case optionalExpression(Expression?)
        case casePairCursor([CaseWhenPair], index: Int)
        case aggregate(AggregateFunction)
        case arrayAggregateTail([SortKey]?, distinct: Bool)
        case sortKeyCursor([SortKey], index: Int)
        case sortKey(SortKey)
        case sortKeyTail(SortDirection, NullOrdering?)
    }

    static func encode(
        _ encodingStep: consuming EncodingStep,
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        switch consume encodingStep {
        case .expression(let expression):
            try begin(expression, writer: &writer, encodingSteps: &encodingSteps)

        case .endNestedValue:
            writer.endNestedValue()

        case .literal(let literal):
            try QueryIRWireFormat.encodeLiteral(literal, into: &writer)

        case .select(let query):
            try beginSelect(query, writer: &writer, encodingSteps: &encodingSteps)

        case .dataSource(let source):
            try beginDataSource(source, writer: &writer, encodingSteps: &encodingSteps)

        case .graphPattern(let pattern):
            try beginGraphPattern(pattern, writer: &writer, encodingSteps: &encodingSteps)

        case .dataType(let type):
            try QueryIRWireFormat.encodeDataType(type, into: &writer)

        case .string(let value):
            try writer.writeString(value)

        case .optionalString(let value):
            try QueryIRWireFormat.writeOptionalString(value, into: &writer)

        case .sparqlVariable(let value):
            try QueryIRWireFormat.writeSPARQLVariableName(value, into: &writer)

        case .bool(let value):
            writer.writeBool(value)

        case .byte(let value):
            writer.writeUInt8(value)

        case .optionalInt(let value):
            try QueryIRWireFormat.writeOptionalInt(value, into: &writer)

        case .optionalUInt64(let value):
            QueryIRWireFormat.writeOptionalUInt64(value, into: &writer)

        case .optionalAccessPath(let value):
            guard let value else {
                writer.writeBool(false)
                return
            }
            writer.writeBool(true)
            try QueryIRWireFormat.encodeAccessPath(value, into: &writer)

        case .projection(let projection):
            try beginProjection(projection, writer: &writer, encodingSteps: &encodingSteps)

        case .projectionItemCursor(let items, let index):
            guard index < items.count else { return }
            let projectionItem = items[index]
            encodingSteps.append(.projectionItemCursor(items, index: index + 1))
            encodingSteps.append(.projectionItemTail(projectionItem.alias))
            encodingSteps.append(.expression(projectionItem.expression))

        case .projectionItemTail(let alias):
            try QueryIRWireFormat.writeOptionalString(alias, into: &writer)

        case .optionalExpressionArray(let values):
            guard let values else {
                writer.writeBool(false)
                return
            }
            writer.writeBool(true)
            encodingSteps.append(.expressionArray(values))

        case .optionalSortKeyArray(let values):
            guard let values else {
                writer.writeBool(false)
                return
            }
            writer.writeBool(true)
            try writer.writeCount(values.count)
            encodingSteps.append(.sortKeyCursor(values, index: 0))

        case .optionalNamedSubqueryArray(let values):
            guard let values else {
                writer.writeBool(false)
                return
            }
            writer.writeBool(true)
            try writer.writeCount(values.count)
            encodingSteps.append(.namedSubqueryCursor(values, index: 0))

        case .namedSubqueryCursor(let values, let index):
            guard index < values.count else { return }
            encodingSteps.append(.namedSubqueryCursor(values, index: index + 1))
            encodingSteps.append(.namedSubquery(values[index]))

        case .namedSubquery(let subquery):
            try writer.writeString(subquery.name)
            try QueryIRWireFormat.writeOptionalStrings(
                subquery.columns,
                into: &writer
            )
            encodingSteps.append(.namedSubqueryTail(subquery.materialized))
            encodingSteps.append(.select(subquery.query))

        case .namedSubqueryTail(let materialized):
            guard let materialized else {
                writer.writeBool(false)
                return
            }
            writer.writeBool(true)
            writer.writeUInt8(materialized == .materialized ? 0 : 1)

        case .sparqlDataset(let dataset):
            try QueryIRWireFormat.encodeSPARQLDataset(dataset, into: &writer)

        case .dataSourceArrayCursor(let sources, let index):
            guard index < sources.count else { return }
            encodingSteps.append(.dataSourceArrayCursor(sources, index: index + 1))
            encodingSteps.append(.dataSource(sources[index]))

        case .join(let join):
            writer.writeUInt8(joinTypeTag(join.type))
            encodingSteps.append(.joinCondition(join.condition))
            encodingSteps.append(.dataSource(join.right))
            encodingSteps.append(.dataSource(join.left))

        case .joinCondition(let condition):
            guard let condition else {
                writer.writeBool(false)
                return
            }
            writer.writeBool(true)
            switch condition {
            case .on(let expression):
                writer.writeUInt8(0)
                encodingSteps.append(.expression(expression))
            case .using(let columns):
                writer.writeUInt8(1)
                try QueryIRWireFormat.writeStrings(columns, into: &writer)
            }

        case .graphTable(let source):
            try writer.writeString(source.graphName)
            encodingSteps.append(.graphTableTail(source.columns, alias: source.alias))
            encodingSteps.append(.matchPattern(source.matchPattern))

        case .graphTableTail(let columns, let alias):
            encodingSteps.append(.optionalString(alias))
            encodingSteps.append(.optionalGraphTableColumns(columns))

        case .optionalGraphTableColumns(let columns):
            guard let columns else {
                writer.writeBool(false)
                return
            }
            writer.writeBool(true)
            try writer.writeCount(columns.count)
            encodingSteps.append(.graphTableColumnCursor(columns, index: 0))

        case .graphTableColumnCursor(let columns, let index):
            guard index < columns.count else { return }
            let column = columns[index]
            encodingSteps.append(.graphTableColumnCursor(columns, index: index + 1))
            encodingSteps.append(.graphTableColumnTail(column.alias))
            encodingSteps.append(.expression(column.expression))

        case .graphTableColumnTail(let alias):
            try writer.writeString(alias)

        case .matchPattern(let pattern):
            try writer.writeCount(pattern.paths.count)
            encodingSteps.append(.optionalExpression(pattern.where))
            encodingSteps.append(.pathPatternCursor(pattern.paths, index: 0))

        case .pathPattern(let pattern):
            try QueryIRWireFormat.writeOptionalString(
                pattern.pathVariable,
                into: &writer
            )
            try writer.writeCount(pattern.elements.count)
            encodingSteps.append(.optionalPathMode(pattern.mode))
            encodingSteps.append(.pathElementCursor(pattern.elements, index: 0))

        case .pathPatternCursor(let patterns, let index):
            guard index < patterns.count else { return }
            encodingSteps.append(.pathPatternCursor(patterns, index: index + 1))
            encodingSteps.append(.pathPattern(patterns[index]))

        case .pathElement(let element):
            try beginPathElement(element, writer: &writer, encodingSteps: &encodingSteps)

        case .pathElementCursor(let elements, let index):
            guard index < elements.count else { return }
            encodingSteps.append(.pathElementCursor(elements, index: index + 1))
            encodingSteps.append(.pathElement(elements[index]))

        case .optionalPathMode(let mode):
            guard let mode else {
                writer.writeBool(false)
                return
            }
            writer.writeBool(true)
            try encodePathMode(mode, writer: &writer)

        case .pathQuantifier(let quantifier):
            try encodePathQuantifier(quantifier, writer: &writer)

        case .nodePattern(let node):
            try QueryIRWireFormat.writeOptionalString(node.variable, into: &writer)
            try QueryIRWireFormat.writeOptionalStrings(node.labels, into: &writer)
            encodingSteps.append(.optionalPropertyBindings(node.properties))

        case .edgePattern(let edge):
            try QueryIRWireFormat.writeOptionalString(edge.variable, into: &writer)
            try QueryIRWireFormat.writeOptionalStrings(edge.labels, into: &writer)
            encodingSteps.append(.byte(edgeDirectionTag(edge.direction)))
            encodingSteps.append(.optionalPropertyBindings(edge.properties))

        case .optionalPropertyBindings(let bindings):
            guard let bindings else {
                writer.writeBool(false)
                return
            }
            writer.writeBool(true)
            try writer.writeCount(bindings.count)
            encodingSteps.append(.propertyBindingCursor(bindings, index: 0))

        case .propertyBindingCursor(let bindings, let index):
            guard index < bindings.count else { return }
            let binding = bindings[index]
            encodingSteps.append(.propertyBindingCursor(bindings, index: index + 1))
            encodingSteps.append(.expression(binding.value))
            try writer.writeString(binding.key)

        case .graphPatternGroupByTail(let expressions, let aggregates):
            encodingSteps.append(.aggregateBindingArray(aggregates))
            encodingSteps.append(.expressionArray(expressions))

        case .aggregateBindingArray(let bindings):
            try writer.writeCount(bindings.count)
            encodingSteps.append(.aggregateBindingCursor(bindings, index: 0))

        case .aggregateBindingCursor(let bindings, let index):
            guard index < bindings.count else { return }
            let binding = bindings[index]
            encodingSteps.append(.aggregateBindingCursor(bindings, index: index + 1))
            encodingSteps.append(.aggregate(binding.aggregate))
            try QueryIRWireFormat.writeSPARQLVariableName(
                binding.variable,
                into: &writer
            )

        case .expressionArray(let values):
            try writer.writeCount(values.count)
            encodingSteps.append(.expressionArrayCursor(values, index: 0))

        case .expressionArrayCursor(let values, let index):
            guard index < values.count else { return }
            encodingSteps.append(.expressionArrayCursor(values, index: index + 1))
            encodingSteps.append(.expression(values[index]))

        case .optionalExpression(let value):
            guard let value else {
                writer.writeBool(false)
                return
            }
            writer.writeBool(true)
            encodingSteps.append(.expression(value))

        case .casePairCursor(let pairs, let index):
            guard index < pairs.count else { return }
            let pair = pairs[index]
            encodingSteps.append(.casePairCursor(pairs, index: index + 1))
            encodingSteps.append(.expression(pair.result))
            encodingSteps.append(.expression(pair.condition))

        case .aggregate(let aggregate):
            try beginAggregate(aggregate, writer: &writer, encodingSteps: &encodingSteps)

        case .arrayAggregateTail(let keys, let distinct):
            guard let keys else {
                writer.writeBool(false)
                writer.writeBool(distinct)
                return
            }
            writer.writeBool(true)
            try writer.writeCount(keys.count)
            encodingSteps.append(.bool(distinct))
            encodingSteps.append(.sortKeyCursor(keys, index: 0))

        case .sortKeyCursor(let keys, let index):
            guard index < keys.count else { return }
            encodingSteps.append(.sortKeyCursor(keys, index: index + 1))
            encodingSteps.append(.sortKey(keys[index]))

        case .sortKey(let key):
            encodingSteps.append(.sortKeyTail(key.direction, key.nulls))
            encodingSteps.append(.expression(key.expression))

        case .sortKeyTail(let direction, let nulls):
            writer.writeUInt8(direction == .ascending ? 0 : 1)
            guard let nulls else {
                writer.writeBool(false)
                return
            }
            writer.writeBool(true)
            writer.writeUInt8(nulls == .first ? 0 : 1)
        }
    }

    static func begin(
        _ expression: Expression,
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        try writer.beginNestedValue()
        encodingSteps.append(.endNestedValue)

        switch expression {
        case .literal(let value):
            writer.writeUInt8(0)
            encodingSteps.append(.literal(value))

        case .column(let value):
            writer.writeUInt8(1)
            try QueryIRWireFormat.writeOptionalString(value.table, into: &writer)
            try writer.writeString(value.column)

        case .variable(let value):
            writer.writeUInt8(2)
            try QueryIRWireFormat.writeSPARQLVariableName(value.name, into: &writer)

        case .parameter(let reference):
            writer.writeUInt8(40)
            switch reference {
            case .position(let position):
                guard position > 0 else {
                    throw .invalidParameterPosition(position)
                }
                writer.writeUInt8(1)
                writer.writeUInt32(position)
            case .name(let name):
                guard !name.isEmpty else {
                    throw .emptyParameterName
                }
                writer.writeUInt8(2)
                try writer.writeString(name)
            }

        case .add(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 3, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .subtract(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 4, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .multiply(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 5, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .divide(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 6, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .modulo(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 7, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .negate(let value):
            enqueueUnaryExpressionEncodingSteps(tag: 8, value: value, writer: &writer, encodingSteps: &encodingSteps)
        case .equal(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 9, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .notEqual(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 10, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .lessThan(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 11, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .lessThanOrEqual(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 12, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .greaterThan(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 13, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .greaterThanOrEqual(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 14, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .and(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 15, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .or(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 16, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .not(let value):
            enqueueUnaryExpressionEncodingSteps(tag: 17, value: value, writer: &writer, encodingSteps: &encodingSteps)
        case .isNull(let value):
            enqueueUnaryExpressionEncodingSteps(tag: 18, value: value, writer: &writer, encodingSteps: &encodingSteps)
        case .isNotNull(let value):
            enqueueUnaryExpressionEncodingSteps(tag: 19, value: value, writer: &writer, encodingSteps: &encodingSteps)

        case .bound(let variable):
            writer.writeUInt8(20)
            try QueryIRWireFormat.writeSPARQLVariableName(variable.name, into: &writer)

        case .like(let value, let pattern):
            writer.writeUInt8(21)
            encodingSteps.append(.string(pattern))
            encodingSteps.append(.expression(value))

        case .regex(let value, let pattern, let flags):
            writer.writeUInt8(22)
            encodingSteps.append(.optionalString(flags))
            encodingSteps.append(.string(pattern))
            encodingSteps.append(.expression(value))

        case .between(let value, let low, let high):
            writer.writeUInt8(23)
            encodingSteps.append(.expression(high))
            encodingSteps.append(.expression(low))
            encodingSteps.append(.expression(value))

        case .inList(let value, let values):
            writer.writeUInt8(24)
            encodingSteps.append(.expressionArray(values))
            encodingSteps.append(.expression(value))

        case .notInList(let value, let values):
            writer.writeUInt8(25)
            encodingSteps.append(.expressionArray(values))
            encodingSteps.append(.expression(value))

        case .inSubquery(let value, let query):
            writer.writeUInt8(26)
            encodingSteps.append(.select(query))
            encodingSteps.append(.expression(value))

        case .aggregate(let aggregate):
            writer.writeUInt8(27)
            encodingSteps.append(.aggregate(aggregate))

        case .function(let function):
            writer.writeUInt8(28)
            try writer.writeString(function.name)
            try writer.writeCount(function.arguments.count)
            encodingSteps.append(.bool(function.distinct))
            encodingSteps.append(.expressionArrayCursor(function.arguments, index: 0))

        case .caseWhen(let pairs, let elseResult):
            writer.writeUInt8(29)
            try writer.writeCount(pairs.count)
            encodingSteps.append(.optionalExpression(elseResult))
            encodingSteps.append(.casePairCursor(pairs, index: 0))

        case .coalesce(let values):
            writer.writeUInt8(30)
            encodingSteps.append(.expressionArray(values))

        case .nullIf(let lhs, let rhs):
            enqueueBinaryExpressionEncodingSteps(tag: 31, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)

        case .cast(let value, let targetType):
            writer.writeUInt8(32)
            encodingSteps.append(.dataType(targetType))
            encodingSteps.append(.expression(value))

        case .triple(let subject, let predicate, let object):
            writer.writeUInt8(33)
            encodingSteps.append(.expression(object))
            encodingSteps.append(.expression(predicate))
            encodingSteps.append(.expression(subject))

        case .isTriple(let value):
            enqueueUnaryExpressionEncodingSteps(tag: 34, value: value, writer: &writer, encodingSteps: &encodingSteps)
        case .subject(let value):
            enqueueUnaryExpressionEncodingSteps(tag: 35, value: value, writer: &writer, encodingSteps: &encodingSteps)
        case .predicate(let value):
            enqueueUnaryExpressionEncodingSteps(tag: 36, value: value, writer: &writer, encodingSteps: &encodingSteps)
        case .object(let value):
            enqueueUnaryExpressionEncodingSteps(tag: 37, value: value, writer: &writer, encodingSteps: &encodingSteps)

        case .subquery(let query):
            writer.writeUInt8(38)
            encodingSteps.append(.select(query))
        case .exists(let query):
            writer.writeUInt8(39)
            encodingSteps.append(.select(query))
        }
    }

    static func beginAggregate(
        _ aggregate: AggregateFunction,
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        switch aggregate {
        case .count(let expression, let distinct):
            writer.writeUInt8(0)
            writer.writeBool(expression != nil)
            encodingSteps.append(.bool(distinct))
            if let expression {
                encodingSteps.append(.expression(expression))
            }
        case .sum(let expression, let distinct):
            writer.writeUInt8(1)
            encodingSteps.append(.bool(distinct))
            encodingSteps.append(.expression(expression))
        case .avg(let expression, let distinct):
            writer.writeUInt8(2)
            encodingSteps.append(.bool(distinct))
            encodingSteps.append(.expression(expression))
        case .min(let expression):
            writer.writeUInt8(3)
            encodingSteps.append(.expression(expression))
        case .max(let expression):
            writer.writeUInt8(4)
            encodingSteps.append(.expression(expression))
        case .groupConcat(let expression, let separator, let distinct):
            writer.writeUInt8(5)
            encodingSteps.append(.bool(distinct))
            encodingSteps.append(.optionalString(separator))
            encodingSteps.append(.expression(expression))
        case .sample(let expression):
            writer.writeUInt8(6)
            encodingSteps.append(.expression(expression))
        case .arrayAgg(let expression, let orderBy, let distinct):
            writer.writeUInt8(7)
            encodingSteps.append(.arrayAggregateTail(orderBy, distinct: distinct))
            encodingSteps.append(.expression(expression))
        }
    }

    static func enqueueUnaryExpressionEncodingSteps(
        tag: UInt8,
        value: Expression,
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) {
        writer.writeUInt8(tag)
        encodingSteps.append(.expression(value))
    }

    static func enqueueBinaryExpressionEncodingSteps(
        tag: UInt8,
        lhs: Expression,
        rhs: Expression,
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) {
        writer.writeUInt8(tag)
        encodingSteps.append(.expression(rhs))
        encodingSteps.append(.expression(lhs))
    }

    static func beginSelect(
        _ query: SelectQuery,
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        try writer.beginNestedValue()
        encodingSteps.append(.endNestedValue)
        encodingSteps.append(.sparqlDataset(query.dataset))
        encodingSteps.append(.bool(query.reduced))
        encodingSteps.append(.optionalNamedSubqueryArray(query.subqueries))
        encodingSteps.append(.bool(query.distinct))
        encodingSteps.append(.optionalUInt64(query.offset))
        encodingSteps.append(.optionalUInt64(query.limit))
        encodingSteps.append(.optionalSortKeyArray(query.orderBy))
        encodingSteps.append(.optionalExpression(query.having))
        encodingSteps.append(.optionalExpressionArray(query.groupBy))
        encodingSteps.append(.optionalExpression(query.filter))
        encodingSteps.append(.optionalAccessPath(query.accessPath))
        encodingSteps.append(.dataSource(query.source))
        encodingSteps.append(.projection(query.projection))
    }

    static func beginProjection(
        _ projection: Projection,
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        switch projection {
        case .all:
            writer.writeUInt8(0)
        case .allFrom(let source):
            writer.writeUInt8(1)
            try writer.writeString(source)
        case .items(let items):
            writer.writeUInt8(2)
            try writer.writeCount(items.count)
            encodingSteps.append(.projectionItemCursor(items, index: 0))
        case .distinctItems(let items):
            writer.writeUInt8(3)
            try writer.writeCount(items.count)
            encodingSteps.append(.projectionItemCursor(items, index: 0))
        }
    }

    static func beginDataSource(
        _ source: DataSource,
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        try writer.beginNestedValue()
        encodingSteps.append(.endNestedValue)
        switch source {
        case .table(let table):
            writer.writeUInt8(0)
            try QueryIRWireFormat.encodeTableRef(table, into: &writer)
        case .logical(let source):
            writer.writeUInt8(1)
            try writer.writeString(source.kindIdentifier)
            try writer.writeString(source.identifier)
            try QueryIRWireFormat.writeOptionalString(source.alias, into: &writer)
        case .subquery(let query, let alias):
            writer.writeUInt8(2)
            encodingSteps.append(.string(alias))
            encodingSteps.append(.select(query))
        case .join(let join):
            writer.writeUInt8(3)
            encodingSteps.append(.join(join))
        case .values(let rows, let columnNames):
            writer.writeUInt8(4)
            try QueryIRWireFormat.writeArray(rows, into: &writer) {
                (row: [Literal], writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try QueryIRWireFormat.writeArray(
                    row,
                    into: &writer,
                    encode: QueryIRWireFormat.encodeLiteral
                )
            }
            try QueryIRWireFormat.writeOptionalStrings(columnNames, into: &writer)
        case .graphTable(let source):
            writer.writeUInt8(5)
            encodingSteps.append(.graphTable(source))
        case .graphPattern(let pattern):
            writer.writeUInt8(6)
            encodingSteps.append(.graphPattern(pattern))
        case .namedGraph(let name, let pattern):
            writer.writeUInt8(7)
            try QueryIRWireFormat.writeSPARQLIRI(name, into: &writer)
            encodingSteps.append(.graphPattern(pattern))
        case .service(let endpoint, let pattern, let silent):
            writer.writeUInt8(8)
            try QueryIRWireFormat.writeSPARQLIRI(endpoint, into: &writer)
            encodingSteps.append(.bool(silent))
            encodingSteps.append(.graphPattern(pattern))
        case .union(let sources):
            try enqueueDataSourceEncodingSteps(tag: 9, sources: sources, writer: &writer, encodingSteps: &encodingSteps)
        case .unionAll(let sources):
            try enqueueDataSourceEncodingSteps(tag: 10, sources: sources, writer: &writer, encodingSteps: &encodingSteps)
        case .intersect(let sources):
            try enqueueDataSourceEncodingSteps(tag: 11, sources: sources, writer: &writer, encodingSteps: &encodingSteps)
        case .except(let lhs, let rhs):
            writer.writeUInt8(12)
            encodingSteps.append(.dataSource(rhs))
            encodingSteps.append(.dataSource(lhs))
        }
    }

    static func enqueueDataSourceEncodingSteps(
        tag: UInt8,
        sources: [DataSource],
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        writer.writeUInt8(tag)
        try writer.writeCount(sources.count)
        encodingSteps.append(.dataSourceArrayCursor(sources, index: 0))
    }

    static func beginPathElement(
        _ element: PathElement,
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        switch element {
        case .node(let node):
            writer.writeUInt8(0)
            encodingSteps.append(.nodePattern(node))
        case .edge(let edge):
            writer.writeUInt8(1)
            encodingSteps.append(.edgePattern(edge))
        case .quantified(let pattern, let quantifier):
            writer.writeUInt8(2)
            encodingSteps.append(.pathQuantifier(quantifier))
            encodingSteps.append(.pathPattern(pattern))
        case .alternation(let patterns):
            writer.writeUInt8(3)
            try writer.writeCount(patterns.count)
            encodingSteps.append(.pathPatternCursor(patterns, index: 0))
        }
    }

    static func beginGraphPattern(
        _ pattern: GraphPattern,
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        try writer.beginNestedValue()
        encodingSteps.append(.endNestedValue)
        switch pattern {
        case .basic(let basicGraphPattern):
            writer.writeUInt8(0)
            try QueryIRWireFormat.writeArray(
                basicGraphPattern.elements,
                into: &writer
            ) {
                (
                    element: BasicGraphPatternElement,
                    writer: inout DatabaseWireWriter
                ) throws(DatabaseWireError) in
                switch element {
                case .triple(let triple):
                    writer.writeUInt8(0)
                    try QueryIRWireFormat.encodeTriplePattern(
                        triple,
                        into: &writer
                    )
                case .propertyPath(let pathPattern):
                    writer.writeUInt8(1)
                    try QueryIRWireFormat.encodeSPARQLTerm(
                        pathPattern.subject,
                        into: &writer
                    )
                    try QueryIRWireFormat.encodePropertyPath(
                        pathPattern.path,
                        into: &writer
                    )
                    try QueryIRWireFormat.encodeSPARQLTerm(
                        pathPattern.object,
                        into: &writer
                    )
                }
            }
        case .join(let lhs, let rhs):
            enqueueBinaryGraphPatternEncodingSteps(tag: 1, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .optional(let lhs, let rhs):
            enqueueBinaryGraphPatternEncodingSteps(tag: 2, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .union(let lhs, let rhs):
            enqueueBinaryGraphPatternEncodingSteps(tag: 3, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .filter(let pattern, let expression):
            writer.writeUInt8(4)
            encodingSteps.append(.expression(expression))
            encodingSteps.append(.graphPattern(pattern))
        case .minus(let lhs, let rhs):
            enqueueBinaryGraphPatternEncodingSteps(tag: 5, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        case .graph(let name, let pattern):
            writer.writeUInt8(6)
            try QueryIRWireFormat.encodeSPARQLTerm(name, into: &writer)
            encodingSteps.append(.graphPattern(pattern))
        case .service(let endpoint, let pattern, let silent):
            writer.writeUInt8(7)
            try QueryIRWireFormat.writeSPARQLIRI(endpoint, into: &writer)
            encodingSteps.append(.bool(silent))
            encodingSteps.append(.graphPattern(pattern))
        case .bind(let pattern, let variable, let expression):
            writer.writeUInt8(8)
            encodingSteps.append(.expression(expression))
            encodingSteps.append(.sparqlVariable(variable))
            encodingSteps.append(.graphPattern(pattern))
        case .values(let variables, let bindings):
            writer.writeUInt8(9)
            try QueryIRWireFormat.writeArray(variables, into: &writer) {
                (variable: String, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try QueryIRWireFormat.writeSPARQLVariableName(variable, into: &writer)
            }
            try QueryIRWireFormat.writeArray(bindings, into: &writer) {
                (row: [Literal?], writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try QueryIRWireFormat.writeArray(row, into: &writer) {
                    (value: Literal?, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                    try QueryIRWireFormat.writeOptional(
                        value,
                        into: &writer,
                        encode: QueryIRWireFormat.encodeLiteral
                    )
                }
            }
        case .subquery(let query):
            writer.writeUInt8(10)
            encodingSteps.append(.select(query))
        case .groupBy(let pattern, let expressions, let aggregates):
            writer.writeUInt8(11)
            encodingSteps.append(.graphPatternGroupByTail(expressions, aggregates))
            encodingSteps.append(.graphPattern(pattern))
        case .lateral(let lhs, let rhs):
            enqueueBinaryGraphPatternEncodingSteps(tag: 12, lhs: lhs, rhs: rhs, writer: &writer, encodingSteps: &encodingSteps)
        }
    }

    static func enqueueBinaryGraphPatternEncodingSteps(
        tag: UInt8,
        lhs: GraphPattern,
        rhs: GraphPattern,
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) {
        writer.writeUInt8(tag)
        encodingSteps.append(.graphPattern(rhs))
        encodingSteps.append(.graphPattern(lhs))
    }

    static func joinTypeTag(_ type: JoinType) -> UInt8 {
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

    static func edgeDirectionTag(_ direction: EdgeDirection) -> UInt8 {
        switch direction {
        case .outgoing: return 0
        case .incoming: return 1
        case .undirected: return 2
        case .any: return 3
        }
    }

    static func encodePathQuantifier(
        _ quantifier: PathQuantifier,
        writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch quantifier {
        case .exactly(let count):
            writer.writeUInt8(0)
            try QueryIRWireFormat.writeInt(count, into: &writer)
        case .range(let minimum, let maximum):
            writer.writeUInt8(1)
            try QueryIRWireFormat.writeOptionalInt(minimum, into: &writer)
            try QueryIRWireFormat.writeOptionalInt(maximum, into: &writer)
        case .zeroOrMore:
            writer.writeUInt8(2)
        case .oneOrMore:
            writer.writeUInt8(3)
        case .zeroOrOne:
            writer.writeUInt8(4)
        }
    }

    static func encodePathMode(
        _ mode: PathMode,
        writer: inout DatabaseWireWriter
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
            try QueryIRWireFormat.writeInt(count, into: &writer)
        }
    }
}
