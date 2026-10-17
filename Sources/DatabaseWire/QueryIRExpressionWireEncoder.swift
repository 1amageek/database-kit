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
        _ aggregate: AggregateFunction,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeTraversal(startingWith: .aggregate(aggregate), writer: &writer)
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
        let initialDepth = writer.currentNestingDepth
        defer { writer.abandonNestedValues(writer.currentNestingDepth - initialDepth) }
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
        case dataSource(DataSource, allowSet: Bool = false)
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
        case projection([ProjectionItem])
        case projectionItemCursor([ProjectionItem], index: Int)
        case projectionItemTail(String?)
        case quantifier(SelectQuantifier)
        case pagination(QueryPagination)
        case optionalCount(QueryCount?)
        case count(QueryCount)
        case optionalLimit(QueryLimit?)
        case valuesCursor([[Expression]], index: Int)
        case optionalExpressionArray([Expression]?)
        case optionalSortKeyArray([SortKey]?)
        case optionalNamedSubqueryArray([NamedSubquery]?)
        case namedSubqueryCursor([NamedSubquery], index: Int)
        case namedSubquery(NamedSubquery)
        case namedSubqueryTail(NamedSubquery)
        case sparqlDataset(SPARQLDataset)
        case join(JoinClause)
        case joinCondition(JoinCondition?)
        case graphTable(GraphTableSource)
        case graphTableTail([GraphTableColumn]?)
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
        case caseWhenTail([CaseWhenPair], Expression?)
        case grouping(GroupingElement)
        case groupingArray([GroupingElement])
        case groupingCursor([GroupingElement], Int)
        case groupingSetsCursor([[GroupingElement]], Int)
        case expressionUnitsCursor([[Expression]], Int)
        case optionalGroupingArray([GroupingElement]?)
        case sqlAggregate(SQLAggregateCall)
        case sortKeyArray([SortKey])
        case window(WindowCall)
        case windowReference(WindowReference)
        case specification(WindowSpecification)
        case namedWindows([NamedWindow], Int)
        case windowFrame(WindowFrame?)
        case windowBound(WindowFrameBound)
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
        case .caseWhenTail(let pairs, let fallback):
            try writer.writeCount(pairs.count)
            encodingSteps.append(.optionalExpression(fallback))
            encodingSteps.append(.casePairCursor(pairs, index: 0))

        case .expression(let expression):
            try begin(expression, writer: &writer, encodingSteps: &encodingSteps)

        case .endNestedValue:
            try writer.endNestedValue()

        case .literal(let literal):
            try QueryIRWireFormat.encodeLiteral(literal, into: &writer)

        case .select(let query):
            try beginSelect(query, writer: &writer, encodingSteps: &encodingSteps)

        case .dataSource(let source, let allowSet):
            try beginDataSource(source, allowSet: allowSet, writer: &writer, encodingSteps: &encodingSteps)

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
            switch projectionItem {
            case .expression(let expression, let alias):
                writer.writeUInt8(0)
                encodingSteps.append(.projectionItemTail(alias))
                encodingSteps.append(.expression(expression))
            case .wildcard(let qualifier):
                writer.writeUInt8(1)
                try QueryIRWireFormat.writeOptionalString(qualifier, into: &writer)
            }

        case .projectionItemTail(let alias):
            try QueryIRWireFormat.writeOptionalString(alias, into: &writer)

        case .quantifier(let value):
            switch value {
            case .all: writer.writeUInt8(0)
            case .distinct: writer.writeUInt8(1)
            case .distinctOn(let expressions):
                guard !expressions.isEmpty else { throw .invalidQueryStructure(.emptyDistinctOn) }
                writer.writeUInt8(2)
                encodingSteps.append(.expressionArray(expressions))
            }
        case .pagination(let value):
            encodingSteps.append(.optionalLimit(value.limit))
            encodingSteps.append(.optionalCount(value.offset))
        case .optionalCount(let value):
            writer.writeBool(value != nil)
            if let value { encodingSteps.append(.count(value)) }
        case .count(let value):
            switch value {
            case .fixed(let count): writer.writeUInt8(0); writer.writeUInt64(count)
            case .expression(let expression):
                writer.writeUInt8(1)
                encodingSteps.append(.expression(expression))
            }
        case .optionalLimit(let value):
            writer.writeBool(value != nil)
            if let value {
                switch value {
                case .all: writer.writeUInt8(0)
                case .count(let count, let withTies):
                    writer.writeUInt8(1)
                    writer.writeBool(withTies)
                    encodingSteps.append(.count(count))
                }
            }
        case .valuesCursor(let rows, let index):
            guard index < rows.count else { return }
            encodingSteps.append(.valuesCursor(rows, index: index + 1))
            encodingSteps.append(.expressionArray(rows[index]))

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
            do { try QueryStructuralValidator.validate(subquery) }
            catch { throw .invalidQueryStructure(error) }
            try writer.writeString(subquery.name)
            try QueryIRWireFormat.writeOptionalStrings(
                subquery.columns,
                into: &writer
            )
            encodingSteps.append(.namedSubqueryTail(subquery))
            encodingSteps.append(.select(subquery.query))

        case .namedSubqueryTail(let subquery):
            if let materialized = subquery.materialized {
                writer.writeBool(true)
                writer.writeUInt8(materialized == .materialized ? 0 : 1)
            } else {
                writer.writeBool(false)
            }
            try QueryIRWireFormat.encodeCTEMetadata(subquery, into: &writer)

        case .sparqlDataset(let dataset):
            try QueryIRWireFormat.encodeSPARQLDataset(dataset, into: &writer)

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
            encodingSteps.append(.graphTableTail(source.columns))
            encodingSteps.append(.matchPattern(source.matchPattern))

        case .graphTableTail(let columns):
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

        case .optionalGroupingArray(let values):
            writer.writeBool(values != nil)
            if let values { encodingSteps.append(.groupingArray(values)) }
        case .groupingArray(let values):
            try writer.writeCount(values.count)
            encodingSteps.append(.groupingCursor(values, 0))
        case .groupingCursor(let values, let index):
            guard index < values.count else { return }
            encodingSteps.append(.groupingCursor(values, index + 1))
            encodingSteps.append(.grouping(values[index]))
        case .groupingSetsCursor(let values, let index):
            guard index < values.count else { return }
            encodingSteps.append(.groupingSetsCursor(values, index + 1))
            encodingSteps.append(.groupingArray(values[index]))
        case .expressionUnitsCursor(let values, let index):
            guard index < values.count else { return }
            encodingSteps.append(.expressionUnitsCursor(values, index + 1))
            encodingSteps.append(.expressionArray(values[index]))
        case .grouping(let value):
            try writer.beginNestedValue()
            encodingSteps.append(.endNestedValue)
            switch value {
            case .expression(let expression):
                writer.writeUInt8(0)
                encodingSteps.append(.expression(expression))
            case .rollup(let units), .cube(let units):
                if case .rollup = value { writer.writeUInt8(1) } else { writer.writeUInt8(2) }
                try writer.writeCount(units.count)
                encodingSteps.append(.expressionUnitsCursor(units, 0))
            case .groupingSets(let sets):
                writer.writeUInt8(3)
                try writer.writeCount(sets.count)
                encodingSteps.append(.groupingSetsCursor(sets, 0))
            }
        case .sortKeyArray(let keys):
            try writer.writeCount(keys.count)
            encodingSteps.append(.sortKeyCursor(keys, index: 0))
        case .sqlAggregate(let call):
            try writer.writeString(call.function.rawValue)
            try QueryIRWireFormat.writeOptionalString(call.schema, into: &writer)
            encodingSteps.append(.optionalSortKeyArray(call.withinGroup))
            encodingSteps.append(.optionalExpression(call.filter))
            encodingSteps.append(.sortKeyArray(call.orderBy))
            encodingSteps.append(.bool(call.distinct))
            encodingSteps.append(.expressionArray(call.arguments))
        case .window(let call):
            encodingSteps.append(.windowReference(call.reference))
            switch call.function {
            case .aggregate(let aggregate):
                writer.writeUInt8(0)
                encodingSteps.append(.sqlAggregate(aggregate))
            case .analytic(let function, let arguments):
                writer.writeUInt8(1)
                try writer.writeString(function.rawValue)
                encodingSteps.append(.expressionArray(arguments))
            }
        case .windowReference(let reference):
            switch reference {
            case .named(let name): writer.writeUInt8(0); try writer.writeString(name)
            case .specification(let value):
                writer.writeUInt8(1)
                encodingSteps.append(.specification(value))
            }
        case .specification(let value):
            try QueryIRWireFormat.writeOptionalString(value.inheritedName, into: &writer)
            encodingSteps.append(.windowFrame(value.frame))
            encodingSteps.append(.sortKeyArray(value.orderBy))
            encodingSteps.append(.expressionArray(value.partitionBy))
        case .namedWindows(let values, let index):
            if index == 0 { try writer.writeCount(values.count) }
            guard index < values.count else { return }
            try writer.writeString(values[index].name)
            encodingSteps.append(.namedWindows(values, index + 1))
            encodingSteps.append(.specification(values[index].specification))
        case .windowFrame(let value):
            writer.writeBool(value != nil)
            guard let value else { return }
            switch value.mode {
            case .rows: writer.writeUInt8(0)
            case .range: writer.writeUInt8(1)
            case .groups: writer.writeUInt8(2)
            }
            let exclusion: UInt8
            switch value.exclusion {
            case .noOthers: exclusion = 0
            case .currentRow: exclusion = 1
            case .group: exclusion = 2
            case .ties: exclusion = 3
            }
            encodingSteps.append(.byte(exclusion))
            encodingSteps.append(.windowBound(value.end))
            encodingSteps.append(.windowBound(value.start))
        case .windowBound(let value):
            switch value {
            case .unboundedPreceding: writer.writeUInt8(0)
            case .preceding(let expression): writer.writeUInt8(1); encodingSteps.append(.expression(expression))
            case .currentRow: writer.writeUInt8(2)
            case .following(let expression): writer.writeUInt8(3); encodingSteps.append(.expression(expression))
            case .unboundedFollowing: writer.writeUInt8(4)
            }
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
        case .collate(let value, let collation):
            writer.writeUInt8(56)
            writer.writeUInt8(collation == .c ? 0 : 1)
            encodingSteps.append(.expression(value))
        case .arraySubquery(let query):
            writer.writeUInt8(57)
            encodingSteps.append(.select(query))
        case .wholeRow(let source):
            writer.writeUInt8(58)
            try writer.writeString(source)
        case .field(let value, let name):
            writer.writeUInt8(59)
            try writer.writeString(name)
            encodingSteps.append(.expression(value))
        case .fieldExpansion(let value):
            writer.writeUInt8(60)
            encodingSteps.append(.expression(value))
        case .array(let values):
            writer.writeUInt8(41)
            encodingSteps.append(.expressionArray(values))
        case .row(let values):
            writer.writeUInt8(42)
            encodingSteps.append(.expressionArray(values))
        case .arrayAccess(let base, let subscripts):
            guard (1...6).contains(subscripts.count) else { throw .invalidQueryIRWireState }
            writer.writeUInt8(53)
            try writer.writeCount(subscripts.count)
            for subscriptValue in subscripts {
                switch subscriptValue {
                case .index: writer.writeUInt8(0)
                case .slice(let lower, let upper):
                    writer.writeUInt8(1)
                    writer.writeBool(lower != nil)
                    writer.writeBool(upper != nil)
                }
            }
            for subscriptValue in subscripts.reversed() {
                switch subscriptValue {
                case .index(let value): encodingSteps.append(.expression(value))
                case .slice(let lower, let upper):
                    if let upper { encodingSteps.append(.expression(upper)) }
                    if let lower { encodingSteps.append(.expression(lower)) }
                }
            }
            encodingSteps.append(.expression(base))
        case .collectionOperation(let operation, let left, let right):
            writer.writeUInt8(54)
            writer.writeUInt8(operation.rawValue)
            encodingSteps.append(.expression(right))
            encodingSteps.append(.expression(left))
        case .currentValue(let kind, let precision):
            guard precision == nil || kind != .date && (0...6).contains(precision!) else {
                throw .invalidQueryIRWireState
            }
            writer.writeUInt8(52)
            writer.writeUInt8(SQLTemporalWireCodec.encode(kind))
            writer.writeBool(precision != nil)
            if let precision { writer.writeUInt8(UInt8(precision)) }
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

        case .patternMatch(let subject, let pattern, let escape, let kind):
            guard kind.permitsEscape || escape == nil else { throw .invalidQueryIRWireState }
            writer.writeUInt8(50)
            let tag: UInt8
            switch kind {
            case .like: tag = 0
            case .caseInsensitiveLike: tag = 1
            case .similarTo: tag = 2
            case .regularExpression: tag = 3
            case .caseInsensitiveRegularExpression: tag = 4
            }
            writer.writeUInt8(tag)
            writer.writeBool(escape != nil)
            if let escape { encodingSteps.append(.expression(escape)) }
            encodingSteps.append(.expression(pattern))
            encodingSteps.append(.expression(subject))
        case .concatenate(let lhs, let rhs):
            writer.writeUInt8(51)
            encodingSteps.append(.expression(rhs))
            encodingSteps.append(.expression(lhs))

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

        case .grouping(let arguments):
            writer.writeUInt8(61)
            encodingSteps.append(.expressionArray(arguments))
        case .window(let call):
            writer.writeUInt8(62)
            encodingSteps.append(.window(call))
        case .aggregate(let aggregate):
            writer.writeUInt8(27)
            encodingSteps.append(.aggregate(aggregate))

        case .function(let function):
            if function.finalArrayIsVariadic {
                guard !function.arguments.isEmpty else { throw .invalidQueryIRWireState }
                writer.writeUInt8(55)
                try QueryIRWireFormat.writeOptionalString(function.schema, into: &writer)
                try writer.writeString(function.name)
                try writer.writeCount(function.arguments.count)
                writer.writeBool(function.distinct)
            } else {
                writer.writeUInt8(function.schema == nil ? 28 : 43)
                if let schema = function.schema { try writer.writeString(schema) }
                try writer.writeString(function.name)
                try writer.writeCount(function.arguments.count)
                encodingSteps.append(.bool(function.distinct))
            }
            encodingSteps.append(.expressionArrayCursor(function.arguments, index: 0))

        case .caseWhen(let operand, let pairs, let elseResult):
            writer.writeUInt8(operand == nil ? 29 : 44)
            encodingSteps.append(.caseWhenTail(pairs, elseResult))
            if let operand { encodingSteps.append(.expression(operand)) }

        case .greatest(let values), .least(let values):
            if case .greatest = expression { writer.writeUInt8(45) }
            else { writer.writeUInt8(46) }
            encodingSteps.append(.expressionArray(values))

        case .truthTest(let value, let truth, let negated):
            writer.writeUInt8(47)
            encodingSteps.append(.bool(negated))
            encodingSteps.append(.byte(QueryIRPredicateWireCodec.tag(truth)))
            encodingSteps.append(.expression(value))

        case .isDistinctFrom(let lhs, let rhs, let negated):
            writer.writeUInt8(48)
            encodingSteps.append(.bool(negated))
            encodingSteps.append(.expression(rhs))
            encodingSteps.append(.expression(lhs))

        case .quantifiedComparison(let lhs, let comparison, let quantifier, let source):
            writer.writeUInt8(49)
            switch source {
            case .array(let value):
                encodingSteps.append(.expression(value)); encodingSteps.append(.byte(0))
            case .subquery(let query):
                encodingSteps.append(.select(query)); encodingSteps.append(.byte(1))
            }
            encodingSteps.append(.byte(QueryIRPredicateWireCodec.tag(quantifier)))
            encodingSteps.append(.byte(QueryIRPredicateWireCodec.tag(comparison)))
            encodingSteps.append(.expression(lhs))

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
        case .sql(let call):
            writer.writeUInt8(8)
            encodingSteps.append(.sqlAggregate(call))
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
        try QueryIRWireFormat.validateSetEnvelope(query)
        try writer.beginNestedValue()
        encodingSteps.append(.endNestedValue)
        encodingSteps.append(.bool(query.withRecursive))
        encodingSteps.append(.sparqlDataset(query.dataset))
        encodingSteps.append(.bool(query.reduced))
        encodingSteps.append(.pagination(query.pagination))
        encodingSteps.append(.optionalSortKeyArray(query.orderBy))
        encodingSteps.append(.quantifier(query.quantifier))
        encodingSteps.append(.namedWindows(query.windows, 0))
        encodingSteps.append(.optionalExpression(query.having))
        encodingSteps.append(.optionalGroupingArray(query.groupBy))
        encodingSteps.append(.optionalExpression(query.filter))
        encodingSteps.append(.optionalAccessPath(query.accessPath))
        encodingSteps.append(.dataSource(query.source, allowSet: true))
        encodingSteps.append(.projection(query.projection))
        encodingSteps.append(.optionalNamedSubqueryArray(query.subqueries))
    }

    static func beginProjection(
        _ projection: [ProjectionItem],
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        try writer.writeCount(projection.count)
        encodingSteps.append(.projectionItemCursor(projection, index: 0))
    }

    static func beginDataSource(
        _ source: DataSource,
        allowSet: Bool,
        writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        try writer.beginNestedValue()
        encodingSteps.append(.endNestedValue)
        switch source {
        case .table(let table):
            guard table.alias == nil else { throw .invalidQueryStructure(.sourceAliasInTableReference) }
            writer.writeUInt8(0)
            try QueryIRWireFormat.encodeTableRef(table, into: &writer)
        case .logical(let source):
            writer.writeUInt8(1)
            try writer.writeString(source.kindIdentifier)
            try writer.writeString(source.identifier)
        case .subquery(let query):
            writer.writeUInt8(15)
            encodingSteps.append(.select(query))
        case .join(let join):
            writer.writeUInt8(3)
            encodingSteps.append(.join(join))
        case .values(let rows):
            writer.writeUInt8(14)
            try writer.writeCount(rows.count)
            let hasDirectExpansion = rows.contains { row in
                row.contains { if case .fieldExpansion = $0 { return true }; return false }
            }
            if !hasDirectExpansion, let first = rows.first {
                for (index, row) in rows.enumerated() where row.count != first.count {
                    throw .invalidQueryStructure(.invalidValuesRowArity(row: index, expected: first.count, actual: row.count))
                }
            }
            encodingSteps.append(.valuesCursor(rows, index: 0))
        case .aliased(let source, let name, let columns):
            writer.writeUInt8(16)
            try writer.writeString(name)
            try QueryIRWireFormat.writeOptionalStrings(columns, into: &writer)
            encodingSteps.append(.dataSource(source))
        case .tableFunction(let source):
            do { try QueryStructuralValidator.validate(source) }
            catch { throw .invalidQueryStructure(error) }
            writer.writeUInt8(18)
            writer.writeBool(source.withOrdinality)
            encodingSteps.append(.expression(.function(source.function)))
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
        case .setOperation(let operation, let quantifier, let left, let right):
            guard allowSet else { throw .invalidQueryStructure(.invalidSetQueryEnvelope) }
            writer.writeUInt8(17)
            writer.writeUInt8(operation == .union ? 0 : operation == .intersect ? 1 : 2)
            writer.writeUInt8(quantifier == .all ? 0 : 1)
            encodingSteps.append(.select(right))
            encodingSteps.append(.select(left))
        #if DATABASE_KIT_MULTI_BASE
        case .base(let baseID, let source):
            writer.writeUInt8(13)
            try baseID.encode(into: &writer)
            encodingSteps.append(.dataSource(source))
        #endif
        }
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
