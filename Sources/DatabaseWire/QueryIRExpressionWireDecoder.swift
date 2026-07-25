import DatabaseTypes
import DatabaseKit

/// Decodes expression trees without recursive process-stack growth.
enum QueryIRExpressionWireDecoder {
    static func decode(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Expression {
        var traversal = DecodingTraversal()
        return try traversal.decode(from: &reader)
    }

    static func decodeSelect(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SelectQuery {
        var traversal = DecodingTraversal()
        return try traversal.decodeSelect(from: &reader)
    }

    static func decodeDataSource(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DataSource {
        var traversal = DecodingTraversal()
        return try traversal.decodeDataSource(from: &reader)
    }

    static func decodeGraphPattern(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> GraphPattern {
        var traversal = DecodingTraversal()
        return try traversal.decodeGraphPattern(from: &reader)
    }
}

private extension QueryIRExpressionWireDecoder {
    enum UnaryKind {
        case negate
        case not
        case isNull
        case isNotNull
        case isTriple
        case subject
        case predicate
        case object
    }

    enum BinaryKind {
        case add
        case subtract
        case multiply
        case divide
        case modulo
        case equal
        case notEqual
        case lessThan
        case lessThanOrEqual
        case greaterThan
        case greaterThanOrEqual
        case and
        case or
        case nullIf
    }

    enum ListKind {
        case `in`
        case notIn
    }

    enum SelectKind {
        case scalar
        case exists
    }

    enum AggregateExpressionKind {
        case sum
        case average
        case minimum
        case maximum
        case sample
    }

    enum ProjectionKind {
        case items
        case distinctItems
    }

    enum DataSourceCollectionKind {
        case union
        case unionAll
        case intersect
    }

    enum GraphPatternBinaryKind {
        case join
        case optional
        case union
        case minus
        case lateral
    }

    enum SelectExpressionField {
        case filter
        case having
    }

    enum SelectExpressionListField {
        case groupBy
    }

    struct SelectDecodingState {
        let projection: Projection
        let source: DataSource
        let accessPath: AccessPath?
        var filter: Expression?
        var groupBy: [Expression]?
        var having: Expression?
        var orderBy: [SortKey]?

        init(
            projection: Projection,
            source: DataSource,
            accessPath: AccessPath?
        ) {
            self.projection = projection
            self.source = source
            self.accessPath = accessPath
        }
    }

    /// Owns the final collection buffer while one child is decoded at a time.
    /// Moving this cursor between decoding steps keeps the traversal stack proportional to
    /// nesting depth and avoids rematerializing a completed flat-stack slice.
    struct CollectionCursor<Element> {
        var remaining: Int
        var values: [Element]

        init(count: Int) {
            self.remaining = count
            self.values = []
            self.values.reserveCapacity(count)
        }

        mutating func append(
            _ value: consuming Element
        ) throws(DatabaseWireError) {
            guard remaining > 0 else {
                throw .invalidQueryIRWireState
            }
            values.append(consume value)
            remaining -= 1
        }
    }

    enum DecodingStep {
        case expression
        case select
        case dataSource
        case graphPattern
        case endNestedValue
        case assembleUnary(UnaryKind)
        case assembleBinary(BinaryKind)
        case assembleBetween
        case assembleTriple
        case likeTail
        case regexTail
        case listTail(ListKind)
        case expressionCursor(CollectionCursor<Expression>)
        case expressionCursorAppend(CollectionCursor<Expression>)
        case assembleList(ListKind)
        case inSubqueryTail
        case inSubqueryFinish(Expression)
        case aggregate
        case aggregateCountTail
        case aggregateExpressionTail(AggregateExpressionKind, readsDistinct: Bool)
        case aggregateGroupConcatTail
        case aggregateArrayTail
        case aggregateArrayFinish
        case sortKeyCursor(CollectionCursor<SortKey>)
        case sortKeyCursorAppend(CollectionCursor<SortKey>)
        case sortKey
        case sortKeyTail
        case functionTail(name: String)
        case caseWhenPairCursor(CollectionCursor<CaseWhenPair>)
        case caseWhenPairAfterCondition(CollectionCursor<CaseWhenPair>)
        case caseWhenPairAppend(
            CollectionCursor<CaseWhenPair>,
            condition: Expression
        )
        case caseWhenFinish([CaseWhenPair])
        case assembleCoalesce
        case castTail
        case selectExpression(SelectKind)
        case selectExpressionFinish(SelectKind)
        case selectAfterProjection
        case selectAfterSource(Projection)
        case selectAdvance(SelectDecodingState, stage: Int)
        case selectStoreExpression(SelectDecodingState, SelectExpressionField, nextStage: Int)
        case selectStoreExpressionList(SelectDecodingState, SelectExpressionListField, nextStage: Int)
        case selectStoreSortKeys(SelectDecodingState, nextStage: Int)
        case selectFinish(SelectDecodingState, limit: UInt64?, offset: UInt64?, distinct: Bool, hasSubqueries: Bool)
        case projection
        case projectionItemCursor(CollectionCursor<ProjectionItem>)
        case projectionItemCursorAppend(CollectionCursor<ProjectionItem>)
        case projectionItemTail
        case projectionFinish(ProjectionKind)
        case namedSubqueryCursor(CollectionCursor<NamedSubquery>)
        case namedSubqueryCursorAppend(CollectionCursor<NamedSubquery>)
        case namedSubquery
        case namedSubqueryTail(name: String, columns: [String]?)
        case dataSourceSubqueryTail
        case dataSourceJoinAfterLeft(JoinType)
        case dataSourceJoinAfterRight(JoinType, DataSource)
        case dataSourceJoinCondition(JoinType, DataSource, DataSource)
        case dataSourceJoinOnFinish(JoinType, DataSource, DataSource)
        case dataSourceCursor(CollectionCursor<DataSource>)
        case dataSourceCursorAppend(CollectionCursor<DataSource>)
        case dataSourceCollectionFinish(DataSourceCollectionKind)
        case dataSourceExceptFinish
        case dataSourceGraphPatternFinish
        case dataSourceGraphTableFinish
        case dataSourceNamedGraphFinish(String)
        case dataSourceServiceFinish(String)
        case graphPatternAssembleBinary(GraphPatternBinaryKind)
        case graphPatternFilterFinish
        case graphPatternGraphFinish(SPARQLTerm)
        case graphPatternServiceFinish(String)
        case graphPatternBindAfterPattern
        case graphPatternBindFinish(GraphPattern, String)
        case graphPatternSubqueryFinish
        case graphPatternGroupAfterPattern
        case graphPatternGroupAfterExpressions(GraphPattern)
        case graphPatternGroupFinish(GraphPattern, expressions: [Expression])
        case aggregateBindingCursor(CollectionCursor<AggregateBinding>)
        case aggregateBindingCursorAppend(CollectionCursor<AggregateBinding>)
        case aggregateBinding
        case aggregateBindingFinish(String)
        case graphTable
        case graphTableAfterMatch(String)
        case graphTableColumnCursor(CollectionCursor<GraphTableColumn>)
        case graphTableColumnCursorAppend(CollectionCursor<GraphTableColumn>)
        case graphTableColumnTail
        case graphTableFinish(String, MatchPattern, hasColumns: Bool)
        case matchPattern
        case matchPatternAfterPaths
        case matchPatternFinish([PathPattern])
        case pathPattern
        case pathPatternAfterElements(String?)
        case pathPatternCursor(CollectionCursor<PathPattern>)
        case pathPatternCursorAppend(CollectionCursor<PathPattern>)
        case pathElementCursor(CollectionCursor<PathElement>)
        case pathElementCursorAppend(CollectionCursor<PathElement>)
        case pathElement
        case pathElementNodeFinish
        case pathElementEdgeFinish
        case pathElementQuantifiedFinish
        case pathElementAlternationFinish
        case nodePattern
        case edgePattern
        case propertyBindingCursor(CollectionCursor<PropertyBinding>)
        case propertyBindingCursorAppend(CollectionCursor<PropertyBinding>)
        case propertyBinding
        case propertyBindingFinish(String)
        case nodePatternFinish(String?, [String]?, hasProperties: Bool)
        case edgePatternFinish(String?, [String]?, hasProperties: Bool)
    }

    struct DecodingTraversal {
        private var expressions: [Expression] = []
        private var sortKeys: [SortKey] = []
        private var selectQueries: [SelectQuery] = []
        private var dataSources: [DataSource] = []
        private var graphPatterns: [GraphPattern] = []
        private var projections: [Projection] = []
        private var projectionItems: [ProjectionItem] = []
        private var namedSubqueries: [NamedSubquery] = []
        private var aggregateBindings: [AggregateBinding] = []
        private var graphTableSources: [GraphTableSource] = []
        private var graphTableColumns: [GraphTableColumn] = []
        private var matchPatterns: [MatchPattern] = []
        private var pathPatterns: [PathPattern] = []
        private var pathElements: [PathElement] = []
        private var propertyBindings: [PropertyBinding] = []
        private var nodePatterns: [NodePattern] = []
        private var edgePatterns: [EdgePattern] = []
        private var expressionCollections: [[Expression]] = []
        private var sortKeyCollections: [[SortKey]] = []
        private var projectionItemCollections: [[ProjectionItem]] = []
        private var namedSubqueryCollections: [[NamedSubquery]] = []
        private var dataSourceCollections: [[DataSource]] = []
        private var aggregateBindingCollections: [[AggregateBinding]] = []
        private var graphTableColumnCollections: [[GraphTableColumn]] = []
        private var pathPatternCollections: [[PathPattern]] = []
        private var pathElementCollections: [[PathElement]] = []
        private var propertyBindingCollections: [[PropertyBinding]] = []

        mutating func decode(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> Expression {
            try decodeTraversal(startingWith: .expression, reader: &reader)
            guard expressions.count == 1, sortKeys.isEmpty,
                  let result = expressions.popLast() else {
                throw .invalidQueryIRWireState
            }
            try ensureQueryStacksAreEmpty()
            return result
        }

        mutating func decodeSelect(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> SelectQuery {
            try decodeTraversal(startingWith: .select, reader: &reader)
            guard selectQueries.count == 1,
                  let result = selectQueries.popLast() else {
                throw .invalidQueryIRWireState
            }
            try ensureQueryStacksAreEmpty()
            return result
        }

        mutating func decodeDataSource(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> DataSource {
            try decodeTraversal(startingWith: .dataSource, reader: &reader)
            guard dataSources.count == 1,
                  let result = dataSources.popLast() else {
                throw .invalidQueryIRWireState
            }
            try ensureQueryStacksAreEmpty()
            return result
        }

        mutating func decodeGraphPattern(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> GraphPattern {
            try decodeTraversal(startingWith: .graphPattern, reader: &reader)
            guard graphPatterns.count == 1,
                  let result = graphPatterns.popLast() else {
                throw .invalidQueryIRWireState
            }
            try ensureQueryStacksAreEmpty()
            return result
        }

        private mutating func decodeTraversal(
            startingWith initialStep: DecodingStep,
            reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            var decodingSteps: [DecodingStep] = [initialStep]
            while let decodingStep = decodingSteps.popLast() {
                try decode(decodingStep, reader: &reader, decodingSteps: &decodingSteps)
            }
        }

        private mutating func decode(
            _ decodingStep: consuming DecodingStep,
            reader: inout DatabaseWireReader,
            decodingSteps: inout [DecodingStep]
        ) throws(DatabaseWireError) {
            switch consume decodingStep {
            case .expression:
                try beginExpression(reader: &reader, decodingSteps: &decodingSteps)

            case .select:
                try beginSelect(reader: &reader, decodingSteps: &decodingSteps)

            case .dataSource:
                try beginDataSource(reader: &reader, decodingSteps: &decodingSteps)

            case .graphPattern:
                try beginGraphPattern(reader: &reader, decodingSteps: &decodingSteps)

            case .endNestedValue:
                try reader.endNestedValue()

            case .assembleUnary(let kind):
                let value = try popExpression()
                expressions.append(unary(kind, value: value))

            case .assembleBinary(let kind):
                let rhs = try popExpression()
                let lhs = try popExpression()
                expressions.append(binary(kind, lhs: lhs, rhs: rhs))

            case .assembleBetween:
                let high = try popExpression()
                let low = try popExpression()
                let value = try popExpression()
                expressions.append(
                    .between(value, low: low, high: high)
                )

            case .assembleTriple:
                let object = try popExpression()
                let predicate = try popExpression()
                let subject = try popExpression()
                expressions.append(
                    .triple(
                        subject: subject,
                        predicate: predicate,
                        object: object
                    )
                )

            case .likeTail:
                let value = try popExpression()
                expressions.append(
                    .like(value, pattern: try reader.readString())
                )

            case .regexTail:
                let value = try popExpression()
                expressions.append(
                    .regex(
                        value,
                        pattern: try reader.readString(),
                        flags: try QueryIRWireFormat.readOptionalString(from: &reader)
                    )
                )

            case .listTail(let kind):
                let count = try reader.readCount()
                decodingSteps.append(.assembleList(kind))
                decodingSteps.append(.expressionCursor(CollectionCursor(count: count)))

            case .expressionCursor(let cursor):
                guard cursor.remaining > 0 else {
                    expressionCollections.append(cursor.values)
                    return
                }
                decodingSteps.append(.expressionCursorAppend(cursor))
                decodingSteps.append(.expression)

            case .expressionCursorAppend(var cursor):
                try cursor.append(try popExpression())
                decodingSteps.append(.expressionCursor(cursor))

            case .assembleList(let kind):
                let values = try popExpressionCollection()
                let value = try popExpression()
                switch kind {
                case .in:
                    expressions.append(.inList(value, values: values))
                case .notIn:
                    expressions.append(.notInList(value, values: values))
                }

            case .inSubqueryTail:
                let value = try popExpression()
                decodingSteps.append(.inSubqueryFinish(value))
                decodingSteps.append(.select)

            case .inSubqueryFinish(let value):
                expressions.append(
                    .inSubquery(value, subquery: try popSelectQuery())
                )

            case .aggregate:
                try beginAggregate(reader: &reader, decodingSteps: &decodingSteps)

            case .aggregateCountTail:
                let value = try popExpression()
                expressions.append(
                    .aggregate(.count(value, distinct: try reader.readBool()))
                )

            case .aggregateExpressionTail(let kind, let readsDistinct):
                let value = try popExpression()
                let distinct = readsDistinct ? try reader.readBool() : false
                expressions.append(
                    .aggregate(
                        aggregateExpression(kind, value: value, distinct: distinct)
                    )
                )

            case .aggregateGroupConcatTail:
                let value = try popExpression()
                expressions.append(
                    .aggregate(
                        .groupConcat(
                            value,
                            separator: try QueryIRWireFormat.readOptionalString(from: &reader),
                            distinct: try reader.readBool()
                        )
                    )
                )

            case .aggregateArrayTail:
                guard try reader.readBool() else {
                    let value = try popExpression()
                    expressions.append(
                        .aggregate(
                            .arrayAgg(
                                value,
                                orderBy: nil,
                                distinct: try reader.readBool()
                            )
                        )
                    )
                    return
                }
                let count = try reader.readCount()
                decodingSteps.append(.aggregateArrayFinish)
                decodingSteps.append(.sortKeyCursor(CollectionCursor(count: count)))

            case .aggregateArrayFinish:
                let keys = try popSortKeyCollection()
                let value = try popExpression()
                expressions.append(
                    .aggregate(
                        .arrayAgg(
                            value,
                            orderBy: keys,
                            distinct: try reader.readBool()
                        )
                    )
                )

            case .sortKeyCursor(let cursor):
                guard cursor.remaining > 0 else {
                    sortKeyCollections.append(cursor.values)
                    return
                }
                decodingSteps.append(.sortKeyCursorAppend(cursor))
                decodingSteps.append(.sortKey)

            case .sortKeyCursorAppend(var cursor):
                try cursor.append(try popSortKey())
                decodingSteps.append(.sortKeyCursor(cursor))

            case .sortKey:
                decodingSteps.append(.sortKeyTail)
                decodingSteps.append(.expression)

            case .sortKeyTail:
                let expression = try popExpression()
                let directionTag = try reader.readUInt8()
                guard directionTag <= 1 else {
                    throw .invalidValueTag(directionTag)
                }
                let nulls: NullOrdering?
                if try reader.readBool() {
                    let tag = try reader.readUInt8()
                    guard tag <= 1 else { throw .invalidValueTag(tag) }
                    nulls = tag == 0 ? .first : .last
                } else {
                    nulls = nil
                }
                sortKeys.append(
                    SortKey(
                        expression,
                        direction: directionTag == 0 ? .ascending : .descending,
                        nulls: nulls
                    )
                )

            case .functionTail(let name):
                expressions.append(
                    .function(
                        FunctionCall(
                            name: name,
                            arguments: try popExpressionCollection(),
                            distinct: try reader.readBool()
                        )
                    )
                )

            case .caseWhenPairCursor(let cursor):
                guard cursor.remaining > 0 else {
                    if try reader.readBool() {
                        decodingSteps.append(.caseWhenFinish(cursor.values))
                        decodingSteps.append(.expression)
                    } else {
                        expressions.append(
                            .caseWhen(cases: cursor.values, elseResult: nil)
                        )
                    }
                    return
                }
                decodingSteps.append(.caseWhenPairAfterCondition(cursor))
                decodingSteps.append(.expression)

            case .caseWhenPairAfterCondition(let cursor):
                let condition = try popExpression()
                decodingSteps.append(
                    .caseWhenPairAppend(
                        cursor,
                        condition: condition
                    )
                )
                decodingSteps.append(.expression)

            case .caseWhenPairAppend(var cursor, let condition):
                let result = try popExpression()
                try cursor.append(
                    CaseWhenPair(condition: condition, result: result)
                )
                decodingSteps.append(.caseWhenPairCursor(cursor))

            case .caseWhenFinish(let pairs):
                expressions.append(
                    .caseWhen(
                        cases: pairs,
                        elseResult: try popExpression()
                    )
                )

            case .assembleCoalesce:
                expressions.append(
                    .coalesce(try popExpressionCollection())
                )

            case .castTail:
                let value = try popExpression()
                expressions.append(
                    .cast(
                        value,
                        targetType: try QueryIRWireFormat.decodeDataType(from: &reader)
                    )
                )

            case .selectExpression(let kind):
                decodingSteps.append(.selectExpressionFinish(kind))
                decodingSteps.append(.select)

            case .selectExpressionFinish(let kind):
                let query = try popSelectQuery()
                switch kind {
                case .scalar:
                    expressions.append(.subquery(query))
                case .exists:
                    expressions.append(.exists(query))
                }

            case .selectAfterProjection:
                let projection = try popProjection()
                decodingSteps.append(.selectAfterSource(projection))
                decodingSteps.append(.dataSource)

            case .selectAfterSource(let projection):
                let source = try popDataSource()
                let accessPath = try QueryIRWireFormat.readOptional(
                    from: &reader,
                    decode: QueryIRWireFormat.decodeAccessPath
                )
                decodingSteps.append(
                    .selectAdvance(
                        SelectDecodingState(
                            projection: projection,
                            source: source,
                            accessPath: accessPath
                        ),
                        stage: 0
                    )
                )

            case .selectAdvance(let state, let stage):
                try advanceSelect(
                    state,
                    stage: stage,
                    reader: &reader,
                    decodingSteps: &decodingSteps
                )

            case .selectStoreExpression(let state, let field, let nextStage):
                var state = state
                let value = try popExpression()
                switch field {
                case .filter: state.filter = value
                case .having: state.having = value
                }
                decodingSteps.append(.selectAdvance(state, stage: nextStage))

            case .selectStoreExpressionList(let state, let field, let nextStage):
                var state = state
                let values = try popExpressionCollection()
                switch field {
                case .groupBy: state.groupBy = values
                }
                decodingSteps.append(.selectAdvance(state, stage: nextStage))

            case .selectStoreSortKeys(let state, let nextStage):
                var state = state
                state.orderBy = try popSortKeyCollection()
                decodingSteps.append(.selectAdvance(state, stage: nextStage))

            case .selectFinish(let state, let limit, let offset, let distinct, let hasSubqueries):
                let subqueries: [NamedSubquery]?
                if hasSubqueries {
                    subqueries = try popNamedSubqueryCollection()
                } else {
                    subqueries = nil
                }
                selectQueries.append(
                    SelectQuery(
                        projection: state.projection,
                        source: state.source,
                        accessPath: state.accessPath,
                        filter: state.filter,
                        groupBy: state.groupBy,
                        having: state.having,
                        orderBy: state.orderBy,
                        limit: limit,
                        offset: offset,
                        distinct: distinct,
                        subqueries: subqueries,
                        reduced: try reader.readBool(),
                        dataset: try QueryIRWireFormat.decodeSPARQLDataset(from: &reader)
                    )
                )

            case .projection:
                try beginProjection(reader: &reader, decodingSteps: &decodingSteps)

            case .projectionItemCursor(let cursor):
                guard cursor.remaining > 0 else {
                    projectionItemCollections.append(cursor.values)
                    return
                }
                decodingSteps.append(.projectionItemCursorAppend(cursor))
                decodingSteps.append(.projectionItemTail)
                decodingSteps.append(.expression)

            case .projectionItemCursorAppend(var cursor):
                try cursor.append(try popProjectionItem())
                decodingSteps.append(.projectionItemCursor(cursor))

            case .projectionItemTail:
                projectionItems.append(
                    ProjectionItem(
                        try popExpression(),
                        alias: try QueryIRWireFormat.readOptionalString(from: &reader)
                    )
                )

            case .projectionFinish(let kind):
                let items = try popProjectionItemCollection()
                switch kind {
                case .items: projections.append(.items(items))
                case .distinctItems: projections.append(.distinctItems(items))
                }

            case .namedSubqueryCursor(let cursor):
                guard cursor.remaining > 0 else {
                    namedSubqueryCollections.append(cursor.values)
                    return
                }
                decodingSteps.append(.namedSubqueryCursorAppend(cursor))
                decodingSteps.append(.namedSubquery)

            case .namedSubqueryCursorAppend(var cursor):
                try cursor.append(try popNamedSubquery())
                decodingSteps.append(.namedSubqueryCursor(cursor))

            case .namedSubquery:
                let name = try reader.readString()
                let columns = try QueryIRWireFormat.readOptionalStrings(from: &reader)
                decodingSteps.append(.namedSubqueryTail(name: name, columns: columns))
                decodingSteps.append(.select)

            case .namedSubqueryTail(let name, let columns):
                let query = try popSelectQuery()
                let materialized: Materialization?
                if try reader.readBool() {
                    let tag = try reader.readUInt8()
                    guard tag <= 1 else { throw .invalidValueTag(tag) }
                    materialized = tag == 0 ? .materialized : .notMaterialized
                } else {
                    materialized = nil
                }
                namedSubqueries.append(
                    NamedSubquery(
                        name: name,
                        columns: columns,
                        query: query,
                        materialized: materialized
                    )
                )

            case .dataSourceSubqueryTail:
                dataSources.append(
                    .subquery(
                        try popSelectQuery(),
                        alias: try reader.readString()
                    )
                )

            case .dataSourceJoinAfterLeft(let type):
                let left = try popDataSource()
                decodingSteps.append(.dataSourceJoinAfterRight(type, left))
                decodingSteps.append(.dataSource)

            case .dataSourceJoinAfterRight(let type, let left):
                let right = try popDataSource()
                decodingSteps.append(.dataSourceJoinCondition(type, left, right))

            case .dataSourceJoinCondition(let type, let left, let right):
                guard try reader.readBool() else {
                    dataSources.append(
                        .join(JoinClause(type: type, left: left, right: right))
                    )
                    return
                }
                switch try reader.readUInt8() {
                case 0:
                    decodingSteps.append(.dataSourceJoinOnFinish(type, left, right))
                    decodingSteps.append(.expression)
                case 1:
                    dataSources.append(
                        .join(
                            JoinClause(
                                type: type,
                                left: left,
                                right: right,
                                condition: .using(
                                    try QueryIRWireFormat.readStrings(from: &reader)
                                )
                            )
                        )
                    )
                case let tag:
                    throw .invalidValueTag(tag)
                }

            case .dataSourceJoinOnFinish(let type, let left, let right):
                dataSources.append(
                    .join(
                        JoinClause(
                            type: type,
                            left: left,
                            right: right,
                            condition: .on(try popExpression())
                        )
                    )
                )

            case .dataSourceCursor(let cursor):
                guard cursor.remaining > 0 else {
                    dataSourceCollections.append(cursor.values)
                    return
                }
                decodingSteps.append(.dataSourceCursorAppend(cursor))
                decodingSteps.append(.dataSource)

            case .dataSourceCursorAppend(var cursor):
                try cursor.append(try popDataSource())
                decodingSteps.append(.dataSourceCursor(cursor))

            case .dataSourceCollectionFinish(let kind):
                let sources = try popDataSourceCollection()
                switch kind {
                case .union: dataSources.append(.union(sources))
                case .unionAll: dataSources.append(.unionAll(sources))
                case .intersect: dataSources.append(.intersect(sources))
                }

            case .dataSourceExceptFinish:
                let rhs = try popDataSource()
                let lhs = try popDataSource()
                dataSources.append(.except(lhs, rhs))

            case .dataSourceGraphPatternFinish:
                dataSources.append(.graphPattern(try popGraphPattern()))

            case .dataSourceGraphTableFinish:
                dataSources.append(.graphTable(try popGraphTableSource()))

            case .dataSourceNamedGraphFinish(let name):
                dataSources.append(
                    .namedGraph(name: name, pattern: try popGraphPattern())
                )

            case .dataSourceServiceFinish(let endpoint):
                dataSources.append(
                    .service(
                        endpoint: endpoint,
                        pattern: try popGraphPattern(),
                        silent: try reader.readBool()
                    )
                )

            case .graphPatternAssembleBinary(let kind):
                let rhs = try popGraphPattern()
                let lhs = try popGraphPattern()
                switch kind {
                case .join: graphPatterns.append(.join(lhs, rhs))
                case .optional: graphPatterns.append(.optional(lhs, rhs))
                case .union: graphPatterns.append(.union(lhs, rhs))
                case .minus: graphPatterns.append(.minus(lhs, rhs))
                case .lateral: graphPatterns.append(.lateral(lhs, rhs))
                }

            case .graphPatternFilterFinish:
                let expression = try popExpression()
                graphPatterns.append(
                    .filter(try popGraphPattern(), expression)
                )

            case .graphPatternGraphFinish(let name):
                graphPatterns.append(
                    .graph(name: name, pattern: try popGraphPattern())
                )

            case .graphPatternServiceFinish(let endpoint):
                graphPatterns.append(
                    .service(
                        endpoint: endpoint,
                        pattern: try popGraphPattern(),
                        silent: try reader.readBool()
                    )
                )

            case .graphPatternBindAfterPattern:
                let pattern = try popGraphPattern()
                let variable = try QueryIRWireFormat.readSPARQLVariableName(
                    from: &reader
                )
                decodingSteps.append(.graphPatternBindFinish(pattern, variable))
                decodingSteps.append(.expression)

            case .graphPatternBindFinish(let pattern, let variable):
                graphPatterns.append(
                    .bind(
                        pattern,
                        variable: variable,
                        expression: try popExpression()
                    )
                )

            case .graphPatternSubqueryFinish:
                graphPatterns.append(.subquery(try popSelectQuery()))

            case .graphPatternGroupAfterPattern:
                let pattern = try popGraphPattern()
                let count = try reader.readCount()
                decodingSteps.append(.graphPatternGroupAfterExpressions(pattern))
                decodingSteps.append(.expressionCursor(CollectionCursor(count: count)))

            case .graphPatternGroupAfterExpressions(let pattern):
                let expressions = try popExpressionCollection()
                let aggregateCount = try reader.readCount()
                decodingSteps.append(
                    .graphPatternGroupFinish(
                        pattern,
                        expressions: expressions
                    )
                )
                decodingSteps.append(
                    .aggregateBindingCursor(
                        CollectionCursor(count: aggregateCount)
                    )
                )

            case .graphPatternGroupFinish(let pattern, let expressions):
                graphPatterns.append(
                    .groupBy(
                        pattern,
                        expressions: expressions,
                        aggregates: try popAggregateBindingCollection()
                    )
                )

            case .aggregateBindingCursor(let cursor):
                guard cursor.remaining > 0 else {
                    aggregateBindingCollections.append(cursor.values)
                    return
                }
                decodingSteps.append(.aggregateBindingCursorAppend(cursor))
                decodingSteps.append(.aggregateBinding)

            case .aggregateBindingCursorAppend(var cursor):
                try cursor.append(try popAggregateBinding())
                decodingSteps.append(.aggregateBindingCursor(cursor))

            case .aggregateBinding:
                let variable = try QueryIRWireFormat.readSPARQLVariableName(
                    from: &reader
                )
                decodingSteps.append(.aggregateBindingFinish(variable))
                decodingSteps.append(.aggregate)

            case .aggregateBindingFinish(let variable):
                guard case .aggregate(let aggregate) = try popExpression() else {
                    throw .invalidQueryIRWireState
                }
                aggregateBindings.append(
                    AggregateBinding(variable: variable, aggregate: aggregate)
                )

            case .graphTable:
                let graphName = try reader.readString()
                decodingSteps.append(.graphTableAfterMatch(graphName))
                decodingSteps.append(.matchPattern)

            case .graphTableAfterMatch(let graphName):
                let matchPattern = try popMatchPattern()
                let hasColumns = try reader.readBool()
                decodingSteps.append(
                    .graphTableFinish(
                        graphName,
                        matchPattern,
                        hasColumns: hasColumns
                    )
                )
                if hasColumns {
                    let columnCount = try reader.readCount()
                    decodingSteps.append(
                        .graphTableColumnCursor(
                            CollectionCursor(count: columnCount)
                        )
                    )
                }

            case .graphTableColumnCursor(let cursor):
                guard cursor.remaining > 0 else {
                    graphTableColumnCollections.append(cursor.values)
                    return
                }
                decodingSteps.append(.graphTableColumnCursorAppend(cursor))
                decodingSteps.append(.graphTableColumnTail)
                decodingSteps.append(.expression)

            case .graphTableColumnCursorAppend(var cursor):
                try cursor.append(try popGraphTableColumn())
                decodingSteps.append(.graphTableColumnCursor(cursor))

            case .graphTableColumnTail:
                graphTableColumns.append(
                    GraphTableColumn(
                        expression: try popExpression(),
                        alias: try reader.readString()
                    )
                )

            case .graphTableFinish(let graphName, let matchPattern, let hasColumns):
                let columns: [GraphTableColumn]?
                if hasColumns {
                    columns = try popGraphTableColumnCollection()
                } else {
                    columns = nil
                }
                graphTableSources.append(
                    GraphTableSource(
                        graphName: graphName,
                        matchPattern: matchPattern,
                        columns: columns,
                        alias: try QueryIRWireFormat.readOptionalString(from: &reader)
                    )
                )

            case .matchPattern:
                let count = try reader.readCount()
                decodingSteps.append(.matchPatternAfterPaths)
                decodingSteps.append(.pathPatternCursor(CollectionCursor(count: count)))

            case .matchPatternAfterPaths:
                let paths = try popPathPatternCollection()
                guard try reader.readBool() else {
                    matchPatterns.append(MatchPattern(paths: paths))
                    return
                }
                decodingSteps.append(.matchPatternFinish(paths))
                decodingSteps.append(.expression)

            case .matchPatternFinish(let paths):
                matchPatterns.append(
                    MatchPattern(paths: paths, where: try popExpression())
                )

            case .pathPattern:
                let pathVariable = try QueryIRWireFormat.readOptionalString(
                    from: &reader
                )
                let count = try reader.readCount()
                decodingSteps.append(.pathPatternAfterElements(pathVariable))
                decodingSteps.append(.pathElementCursor(CollectionCursor(count: count)))

            case .pathPatternAfterElements(let pathVariable):
                let elements = try popPathElementCollection()
                let mode: PathMode?
                if try reader.readBool() {
                    mode = try decodePathMode(reader: &reader)
                } else {
                    mode = nil
                }
                pathPatterns.append(
                    PathPattern(
                        pathVariable: pathVariable,
                        elements: elements,
                        mode: mode
                    )
                )

            case .pathPatternCursor(let cursor):
                guard cursor.remaining > 0 else {
                    pathPatternCollections.append(cursor.values)
                    return
                }
                decodingSteps.append(.pathPatternCursorAppend(cursor))
                decodingSteps.append(.pathPattern)

            case .pathPatternCursorAppend(var cursor):
                try cursor.append(try popPathPattern())
                decodingSteps.append(.pathPatternCursor(cursor))

            case .pathElementCursor(let cursor):
                guard cursor.remaining > 0 else {
                    pathElementCollections.append(cursor.values)
                    return
                }
                decodingSteps.append(.pathElementCursorAppend(cursor))
                decodingSteps.append(.pathElement)

            case .pathElementCursorAppend(var cursor):
                try cursor.append(try popPathElement())
                decodingSteps.append(.pathElementCursor(cursor))

            case .pathElement:
                try beginPathElement(reader: &reader, decodingSteps: &decodingSteps)

            case .pathElementNodeFinish:
                pathElements.append(.node(try popNodePattern()))

            case .pathElementEdgeFinish:
                pathElements.append(.edge(try popEdgePattern()))

            case .pathElementQuantifiedFinish:
                pathElements.append(
                    .quantified(
                        try popPathPattern(),
                        quantifier: try decodePathQuantifier(reader: &reader)
                    )
                )

            case .pathElementAlternationFinish:
                pathElements.append(
                    .alternation(try popPathPatternCollection())
                )

            case .nodePattern:
                try beginNodePattern(reader: &reader, decodingSteps: &decodingSteps)

            case .edgePattern:
                try beginEdgePattern(reader: &reader, decodingSteps: &decodingSteps)

            case .propertyBindingCursor(let cursor):
                guard cursor.remaining > 0 else {
                    propertyBindingCollections.append(cursor.values)
                    return
                }
                decodingSteps.append(.propertyBindingCursorAppend(cursor))
                decodingSteps.append(.propertyBinding)

            case .propertyBindingCursorAppend(var cursor):
                try cursor.append(try popPropertyBinding())
                decodingSteps.append(.propertyBindingCursor(cursor))

            case .propertyBinding:
                let key = try reader.readString()
                decodingSteps.append(.propertyBindingFinish(key))
                decodingSteps.append(.expression)

            case .propertyBindingFinish(let key):
                propertyBindings.append(
                    PropertyBinding(key: key, value: try popExpression())
                )

            case .nodePatternFinish(let variable, let labels, let hasProperties):
                let properties: [PropertyBinding]?
                if hasProperties {
                    properties = try popPropertyBindingCollection()
                } else {
                    properties = nil
                }
                nodePatterns.append(
                    NodePattern(
                        variable: variable,
                        labels: labels,
                        properties: properties
                    )
                )

            case .edgePatternFinish(let variable, let labels, let hasProperties):
                let properties: [PropertyBinding]?
                if hasProperties {
                    properties = try popPropertyBindingCollection()
                } else {
                    properties = nil
                }
                edgePatterns.append(
                    EdgePattern(
                        variable: variable,
                        labels: labels,
                        properties: properties,
                        direction: try decodeEdgeDirection(reader: &reader)
                    )
                )
            }
        }

        private mutating func beginSelect(
            reader: inout DatabaseWireReader,
            decodingSteps: inout [DecodingStep]
        ) throws(DatabaseWireError) {
            try reader.beginNestedValue()
            decodingSteps.append(.endNestedValue)
            decodingSteps.append(.selectAfterProjection)
            decodingSteps.append(.projection)
        }

        private mutating func advanceSelect(
            _ state: SelectDecodingState,
            stage: Int,
            reader: inout DatabaseWireReader,
            decodingSteps: inout [DecodingStep]
        ) throws(DatabaseWireError) {
            switch stage {
            case 0:
                guard try reader.readBool() else {
                    decodingSteps.append(.selectAdvance(state, stage: 1))
                    return
                }
                decodingSteps.append(
                    .selectStoreExpression(state, .filter, nextStage: 1)
                )
                decodingSteps.append(.expression)
            case 1:
                guard try reader.readBool() else {
                    decodingSteps.append(.selectAdvance(state, stage: 2))
                    return
                }
                let count = try reader.readCount()
                decodingSteps.append(
                    .selectStoreExpressionList(
                        state,
                        .groupBy,
                        nextStage: 2
                    )
                )
                decodingSteps.append(.expressionCursor(CollectionCursor(count: count)))
            case 2:
                guard try reader.readBool() else {
                    decodingSteps.append(.selectAdvance(state, stage: 3))
                    return
                }
                decodingSteps.append(
                    .selectStoreExpression(state, .having, nextStage: 3)
                )
                decodingSteps.append(.expression)
            case 3:
                guard try reader.readBool() else {
                    decodingSteps.append(.selectAdvance(state, stage: 4))
                    return
                }
                let count = try reader.readCount()
                decodingSteps.append(
                    .selectStoreSortKeys(
                        state,
                        nextStage: 4
                    )
                )
                decodingSteps.append(.sortKeyCursor(CollectionCursor(count: count)))
            case 4:
                let limit = try QueryIRWireFormat.readOptionalUInt64(from: &reader)
                let offset = try QueryIRWireFormat.readOptionalUInt64(from: &reader)
                let distinct = try reader.readBool()
                let hasSubqueries = try reader.readBool()
                decodingSteps.append(
                    .selectFinish(
                        state,
                        limit: limit,
                        offset: offset,
                        distinct: distinct,
                        hasSubqueries: hasSubqueries
                    )
                )
                if hasSubqueries {
                    let subqueryCount = try reader.readCount()
                    decodingSteps.append(
                        .namedSubqueryCursor(
                            CollectionCursor(count: subqueryCount)
                        )
                    )
                }
            default:
                throw .invalidQueryIRWireState
            }
        }

        private mutating func beginProjection(
            reader: inout DatabaseWireReader,
            decodingSteps: inout [DecodingStep]
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0:
                projections.append(.all)
            case 1:
                projections.append(.allFrom(try reader.readString()))
            case 2:
                let count = try reader.readCount()
                decodingSteps.append(.projectionFinish(.items))
                decodingSteps.append(
                    .projectionItemCursor(CollectionCursor(count: count))
                )
            case 3:
                let count = try reader.readCount()
                decodingSteps.append(.projectionFinish(.distinctItems))
                decodingSteps.append(
                    .projectionItemCursor(CollectionCursor(count: count))
                )
            case let tag:
                throw .invalidValueTag(tag)
            }
        }

        private mutating func beginDataSource(
            reader: inout DatabaseWireReader,
            decodingSteps: inout [DecodingStep]
        ) throws(DatabaseWireError) {
            try reader.beginNestedValue()
            decodingSteps.append(.endNestedValue)
            switch try reader.readUInt8() {
            case 0:
                dataSources.append(
                    .table(try QueryIRWireFormat.decodeTableRef(from: &reader))
                )
            case 1:
                dataSources.append(
                    .logical(
                        LogicalSourceRef(
                            kindIdentifier: try reader.readString(),
                            identifier: try reader.readString(),
                            alias: try QueryIRWireFormat.readOptionalString(from: &reader)
                        )
                    )
                )
            case 2:
                decodingSteps.append(.dataSourceSubqueryTail)
                decodingSteps.append(.select)
            case 3:
                let type = try decodeJoinType(reader: &reader)
                decodingSteps.append(.dataSourceJoinAfterLeft(type))
                decodingSteps.append(.dataSource)
            case 4:
                let rows = try QueryIRWireFormat.readArray(from: &reader) {
                    (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [Literal] in
                    try QueryIRWireFormat.readArray(
                        from: &reader,
                        decode: QueryIRWireFormat.decodeLiteral
                    )
                }
                dataSources.append(
                    .values(
                        rows,
                        columnNames: try QueryIRWireFormat.readOptionalStrings(
                            from: &reader
                        )
                    )
                )
            case 5:
                decodingSteps.append(.dataSourceGraphTableFinish)
                decodingSteps.append(.graphTable)
            case 6:
                decodingSteps.append(.dataSourceGraphPatternFinish)
                decodingSteps.append(.graphPattern)
            case 7:
                let name = try QueryIRWireFormat.readSPARQLIRI(from: &reader)
                decodingSteps.append(.dataSourceNamedGraphFinish(name))
                decodingSteps.append(.graphPattern)
            case 8:
                let endpoint = try QueryIRWireFormat.readSPARQLIRI(from: &reader)
                decodingSteps.append(.dataSourceServiceFinish(endpoint))
                decodingSteps.append(.graphPattern)
            case 9:
                try enqueueDataSourceCollectionDecodingSteps(
                    .union,
                    reader: &reader,
                    decodingSteps: &decodingSteps
                )
            case 10:
                try enqueueDataSourceCollectionDecodingSteps(
                    .unionAll,
                    reader: &reader,
                    decodingSteps: &decodingSteps
                )
            case 11:
                try enqueueDataSourceCollectionDecodingSteps(
                    .intersect,
                    reader: &reader,
                    decodingSteps: &decodingSteps
                )
            case 12:
                decodingSteps.append(.dataSourceExceptFinish)
                decodingSteps.append(.dataSource)
                decodingSteps.append(.dataSource)
            case let tag:
                throw .invalidValueTag(tag)
            }
        }

        private func enqueueDataSourceCollectionDecodingSteps(
            _ kind: DataSourceCollectionKind,
            reader: inout DatabaseWireReader,
            decodingSteps: inout [DecodingStep]
        ) throws(DatabaseWireError) {
            let count = try reader.readCount()
            decodingSteps.append(.dataSourceCollectionFinish(kind))
            decodingSteps.append(.dataSourceCursor(CollectionCursor(count: count)))
        }

        private mutating func beginGraphPattern(
            reader: inout DatabaseWireReader,
            decodingSteps: inout [DecodingStep]
        ) throws(DatabaseWireError) {
            try reader.beginNestedValue()
            decodingSteps.append(.endNestedValue)
            switch try reader.readUInt8() {
            case 0:
                let elements = try QueryIRWireFormat.readArray(
                    from: &reader
                ) {
                    (
                        reader: inout DatabaseWireReader
                    ) throws(DatabaseWireError) -> BasicGraphPatternElement in
                    switch try reader.readUInt8() {
                    case 0:
                        return .triple(
                            try QueryIRWireFormat.decodeTriplePattern(
                                from: &reader
                            )
                        )
                    case 1:
                        return .propertyPath(
                            SPARQLPropertyPathPattern(
                                subject: try QueryIRWireFormat
                                    .decodeSPARQLTerm(from: &reader),
                                path: try QueryIRWireFormat
                                    .decodePropertyPath(from: &reader),
                                object: try QueryIRWireFormat
                                    .decodeSPARQLTerm(from: &reader)
                            )
                        )
                    case let tag:
                        throw .invalidValueTag(tag)
                    }
                }
                graphPatterns.append(
                    .basic(
                        BasicGraphPattern(elements: elements)
                    )
                )
            case 1:
                enqueueBinaryGraphPatternDecodingSteps(.join, decodingSteps: &decodingSteps)
            case 2:
                enqueueBinaryGraphPatternDecodingSteps(.optional, decodingSteps: &decodingSteps)
            case 3:
                enqueueBinaryGraphPatternDecodingSteps(.union, decodingSteps: &decodingSteps)
            case 4:
                decodingSteps.append(.graphPatternFilterFinish)
                decodingSteps.append(.expression)
                decodingSteps.append(.graphPattern)
            case 5:
                enqueueBinaryGraphPatternDecodingSteps(.minus, decodingSteps: &decodingSteps)
            case 6:
                let name = try QueryIRWireFormat.decodeSPARQLTerm(from: &reader)
                decodingSteps.append(.graphPatternGraphFinish(name))
                decodingSteps.append(.graphPattern)
            case 7:
                let endpoint = try QueryIRWireFormat.readSPARQLIRI(from: &reader)
                decodingSteps.append(.graphPatternServiceFinish(endpoint))
                decodingSteps.append(.graphPattern)
            case 8:
                decodingSteps.append(.graphPatternBindAfterPattern)
                decodingSteps.append(.graphPattern)
            case 9:
                let variables = try QueryIRWireFormat.readArray(from: &reader) {
                    (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> String in
                    try QueryIRWireFormat.readSPARQLVariableName(from: &reader)
                }
                let bindings = try QueryIRWireFormat.readArray(from: &reader) {
                    (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [Literal?] in
                    try QueryIRWireFormat.readArray(from: &reader) {
                        (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> Literal? in
                        try QueryIRWireFormat.readOptional(
                            from: &reader,
                            decode: QueryIRWireFormat.decodeLiteral
                        )
                    }
                }
                graphPatterns.append(
                    .values(variables: variables, bindings: bindings)
                )
            case 10:
                decodingSteps.append(.graphPatternSubqueryFinish)
                decodingSteps.append(.select)
            case 11:
                decodingSteps.append(.graphPatternGroupAfterPattern)
                decodingSteps.append(.graphPattern)
            case 12:
                enqueueBinaryGraphPatternDecodingSteps(.lateral, decodingSteps: &decodingSteps)
            case let tag:
                throw .invalidValueTag(tag)
            }
        }

        private func enqueueBinaryGraphPatternDecodingSteps(
            _ kind: GraphPatternBinaryKind,
            decodingSteps: inout [DecodingStep]
        ) {
            decodingSteps.append(.graphPatternAssembleBinary(kind))
            decodingSteps.append(.graphPattern)
            decodingSteps.append(.graphPattern)
        }

        private mutating func beginPathElement(
            reader: inout DatabaseWireReader,
            decodingSteps: inout [DecodingStep]
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0:
                decodingSteps.append(.pathElementNodeFinish)
                decodingSteps.append(.nodePattern)
            case 1:
                decodingSteps.append(.pathElementEdgeFinish)
                decodingSteps.append(.edgePattern)
            case 2:
                decodingSteps.append(.pathElementQuantifiedFinish)
                decodingSteps.append(.pathPattern)
            case 3:
                let count = try reader.readCount()
                decodingSteps.append(.pathElementAlternationFinish)
                decodingSteps.append(
                    .pathPatternCursor(CollectionCursor(count: count))
                )
            case let tag:
                throw .invalidValueTag(tag)
            }
        }

        private mutating func beginNodePattern(
            reader: inout DatabaseWireReader,
            decodingSteps: inout [DecodingStep]
        ) throws(DatabaseWireError) {
            let variable = try QueryIRWireFormat.readOptionalString(from: &reader)
            let labels = try QueryIRWireFormat.readOptionalStrings(from: &reader)
            let hasProperties = try reader.readBool()
            decodingSteps.append(
                .nodePatternFinish(
                    variable,
                    labels,
                    hasProperties: hasProperties
                )
            )
            if hasProperties {
                let propertyCount = try reader.readCount()
                decodingSteps.append(
                    .propertyBindingCursor(
                        CollectionCursor(count: propertyCount)
                    )
                )
            }
        }

        private mutating func beginEdgePattern(
            reader: inout DatabaseWireReader,
            decodingSteps: inout [DecodingStep]
        ) throws(DatabaseWireError) {
            let variable = try QueryIRWireFormat.readOptionalString(from: &reader)
            let labels = try QueryIRWireFormat.readOptionalStrings(from: &reader)
            let hasProperties = try reader.readBool()
            decodingSteps.append(
                .edgePatternFinish(
                    variable,
                    labels,
                    hasProperties: hasProperties
                )
            )
            if hasProperties {
                let propertyCount = try reader.readCount()
                decodingSteps.append(
                    .propertyBindingCursor(
                        CollectionCursor(count: propertyCount)
                    )
                )
            }
        }

        private mutating func beginExpression(
            reader: inout DatabaseWireReader,
            decodingSteps: inout [DecodingStep]
        ) throws(DatabaseWireError) {
            try reader.beginNestedValue()
            let tag = try reader.readUInt8()
            switch tag {
            case 0:
                expressions.append(
                    .literal(try QueryIRWireFormat.decodeLiteral(from: &reader))
                )
                try reader.endNestedValue()
            case 1:
                expressions.append(
                    .column(
                        ColumnRef(
                            table: try QueryIRWireFormat.readOptionalString(from: &reader),
                            column: try reader.readString()
                        )
                    )
                )
                try reader.endNestedValue()
            case 2:
                expressions.append(
                    .variable(
                        Variable(
                            try QueryIRWireFormat.readSPARQLVariableName(from: &reader)
                        )
                    )
                )
                try reader.endNestedValue()
            case 3: enqueueBinaryExpressionDecodingSteps(.add, decodingSteps: &decodingSteps)
            case 4: enqueueBinaryExpressionDecodingSteps(.subtract, decodingSteps: &decodingSteps)
            case 5: enqueueBinaryExpressionDecodingSteps(.multiply, decodingSteps: &decodingSteps)
            case 6: enqueueBinaryExpressionDecodingSteps(.divide, decodingSteps: &decodingSteps)
            case 7: enqueueBinaryExpressionDecodingSteps(.modulo, decodingSteps: &decodingSteps)
            case 8: enqueueUnaryExpressionDecodingSteps(.negate, decodingSteps: &decodingSteps)
            case 9: enqueueBinaryExpressionDecodingSteps(.equal, decodingSteps: &decodingSteps)
            case 10: enqueueBinaryExpressionDecodingSteps(.notEqual, decodingSteps: &decodingSteps)
            case 11: enqueueBinaryExpressionDecodingSteps(.lessThan, decodingSteps: &decodingSteps)
            case 12: enqueueBinaryExpressionDecodingSteps(.lessThanOrEqual, decodingSteps: &decodingSteps)
            case 13: enqueueBinaryExpressionDecodingSteps(.greaterThan, decodingSteps: &decodingSteps)
            case 14: enqueueBinaryExpressionDecodingSteps(.greaterThanOrEqual, decodingSteps: &decodingSteps)
            case 15: enqueueBinaryExpressionDecodingSteps(.and, decodingSteps: &decodingSteps)
            case 16: enqueueBinaryExpressionDecodingSteps(.or, decodingSteps: &decodingSteps)
            case 17: enqueueUnaryExpressionDecodingSteps(.not, decodingSteps: &decodingSteps)
            case 18: enqueueUnaryExpressionDecodingSteps(.isNull, decodingSteps: &decodingSteps)
            case 19: enqueueUnaryExpressionDecodingSteps(.isNotNull, decodingSteps: &decodingSteps)
            case 20:
                expressions.append(
                    .bound(
                        Variable(
                            try QueryIRWireFormat.readSPARQLVariableName(from: &reader)
                        )
                    )
                )
                try reader.endNestedValue()
            case 21:
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.likeTail)
                decodingSteps.append(.expression)
            case 22:
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.regexTail)
                decodingSteps.append(.expression)
            case 23:
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.assembleBetween)
                decodingSteps.append(.expression)
                decodingSteps.append(.expression)
                decodingSteps.append(.expression)
            case 24:
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.listTail(.in))
                decodingSteps.append(.expression)
            case 25:
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.listTail(.notIn))
                decodingSteps.append(.expression)
            case 26:
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.inSubqueryTail)
                decodingSteps.append(.expression)
            case 27:
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.aggregate)
            case 28:
                let name = try reader.readString()
                let count = try reader.readCount()
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.functionTail(name: name))
                decodingSteps.append(.expressionCursor(CollectionCursor(count: count)))
            case 29:
                let pairCount = try reader.readCount()
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(
                    .caseWhenPairCursor(
                        CollectionCursor(count: pairCount)
                    )
                )
            case 30:
                let count = try reader.readCount()
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.assembleCoalesce)
                decodingSteps.append(.expressionCursor(CollectionCursor(count: count)))
            case 31: enqueueBinaryExpressionDecodingSteps(.nullIf, decodingSteps: &decodingSteps)
            case 32:
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.castTail)
                decodingSteps.append(.expression)
            case 33:
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.assembleTriple)
                decodingSteps.append(.expression)
                decodingSteps.append(.expression)
                decodingSteps.append(.expression)
            case 34: enqueueUnaryExpressionDecodingSteps(.isTriple, decodingSteps: &decodingSteps)
            case 35: enqueueUnaryExpressionDecodingSteps(.subject, decodingSteps: &decodingSteps)
            case 36: enqueueUnaryExpressionDecodingSteps(.predicate, decodingSteps: &decodingSteps)
            case 37: enqueueUnaryExpressionDecodingSteps(.object, decodingSteps: &decodingSteps)
            case 38:
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.selectExpression(.scalar))
            case 39:
                decodingSteps.append(.endNestedValue)
                decodingSteps.append(.selectExpression(.exists))
            case 40:
                switch try reader.readUInt8() {
                case 1:
                    let position = try reader.readUInt32()
                    guard position > 0 else {
                        throw .invalidParameterPosition(position)
                    }
                    expressions.append(.parameter(.position(position)))
                case 2:
                    let name = try reader.readString()
                    guard !name.isEmpty else { throw .emptyParameterName }
                    expressions.append(.parameter(.name(name)))
                case let referenceTag:
                    throw .invalidParameterReference(referenceTag)
                }
                try reader.endNestedValue()
            default:
                throw .invalidValueTag(tag)
            }
        }

        private mutating func beginAggregate(
            reader: inout DatabaseWireReader,
            decodingSteps: inout [DecodingStep]
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0:
                guard try reader.readBool() else {
                    expressions.append(
                        .aggregate(.count(nil, distinct: try reader.readBool()))
                    )
                    return
                }
                decodingSteps.append(.aggregateCountTail)
                decodingSteps.append(.expression)
            case 1:
                decodingSteps.append(
                    .aggregateExpressionTail(.sum, readsDistinct: true)
                )
                decodingSteps.append(.expression)
            case 2:
                decodingSteps.append(
                    .aggregateExpressionTail(.average, readsDistinct: true)
                )
                decodingSteps.append(.expression)
            case 3:
                decodingSteps.append(
                    .aggregateExpressionTail(.minimum, readsDistinct: false)
                )
                decodingSteps.append(.expression)
            case 4:
                decodingSteps.append(
                    .aggregateExpressionTail(.maximum, readsDistinct: false)
                )
                decodingSteps.append(.expression)
            case 5:
                decodingSteps.append(.aggregateGroupConcatTail)
                decodingSteps.append(.expression)
            case 6:
                decodingSteps.append(
                    .aggregateExpressionTail(.sample, readsDistinct: false)
                )
                decodingSteps.append(.expression)
            case 7:
                decodingSteps.append(.aggregateArrayTail)
                decodingSteps.append(.expression)
            case let tag:
                throw .invalidValueTag(tag)
            }
        }

        private func enqueueUnaryExpressionDecodingSteps(
            _ kind: UnaryKind,
            decodingSteps: inout [DecodingStep]
        ) {
            decodingSteps.append(.endNestedValue)
            decodingSteps.append(.assembleUnary(kind))
            decodingSteps.append(.expression)
        }

        private func enqueueBinaryExpressionDecodingSteps(
            _ kind: BinaryKind,
            decodingSteps: inout [DecodingStep]
        ) {
            decodingSteps.append(.endNestedValue)
            decodingSteps.append(.assembleBinary(kind))
            decodingSteps.append(.expression)
            decodingSteps.append(.expression)
        }

        private mutating func popExpression() throws(DatabaseWireError) -> Expression {
            guard let value = expressions.popLast() else {
                throw .invalidQueryIRWireState
            }
            return value
        }

        private mutating func popExpressionCollection(
        ) throws(DatabaseWireError) -> [Expression] {
            try Self.popLast(from: &expressionCollections)
        }

        private mutating func popSortKey() throws(DatabaseWireError) -> SortKey {
            try Self.popLast(from: &sortKeys)
        }

        private mutating func popSortKeyCollection(
        ) throws(DatabaseWireError) -> [SortKey] {
            try Self.popLast(from: &sortKeyCollections)
        }

        private mutating func popSelectQuery() throws(DatabaseWireError) -> SelectQuery {
            guard let value = selectQueries.popLast() else {
                throw .invalidQueryIRWireState
            }
            return value
        }

        private mutating func popDataSource() throws(DatabaseWireError) -> DataSource {
            guard let value = dataSources.popLast() else {
                throw .invalidQueryIRWireState
            }
            return value
        }

        private mutating func popDataSourceCollection(
        ) throws(DatabaseWireError) -> [DataSource] {
            try Self.popLast(from: &dataSourceCollections)
        }

        private mutating func popGraphPattern() throws(DatabaseWireError) -> GraphPattern {
            guard let value = graphPatterns.popLast() else {
                throw .invalidQueryIRWireState
            }
            return value
        }

        private mutating func popProjection() throws(DatabaseWireError) -> Projection {
            guard let value = projections.popLast() else {
                throw .invalidQueryIRWireState
            }
            return value
        }

        private mutating func popProjectionItem(
        ) throws(DatabaseWireError) -> ProjectionItem {
            try Self.popLast(from: &projectionItems)
        }

        private mutating func popProjectionItemCollection(
        ) throws(DatabaseWireError) -> [ProjectionItem] {
            try Self.popLast(from: &projectionItemCollections)
        }

        private mutating func popNamedSubquery(
        ) throws(DatabaseWireError) -> NamedSubquery {
            try Self.popLast(from: &namedSubqueries)
        }

        private mutating func popNamedSubqueryCollection(
        ) throws(DatabaseWireError) -> [NamedSubquery] {
            try Self.popLast(from: &namedSubqueryCollections)
        }

        private mutating func popAggregateBinding(
        ) throws(DatabaseWireError) -> AggregateBinding {
            try Self.popLast(from: &aggregateBindings)
        }

        private mutating func popAggregateBindingCollection(
        ) throws(DatabaseWireError) -> [AggregateBinding] {
            try Self.popLast(from: &aggregateBindingCollections)
        }

        private mutating func popGraphTableSource() throws(DatabaseWireError) -> GraphTableSource {
            guard let value = graphTableSources.popLast() else {
                throw .invalidQueryIRWireState
            }
            return value
        }

        private mutating func popGraphTableColumn(
        ) throws(DatabaseWireError) -> GraphTableColumn {
            try Self.popLast(from: &graphTableColumns)
        }

        private mutating func popGraphTableColumnCollection(
        ) throws(DatabaseWireError) -> [GraphTableColumn] {
            try Self.popLast(from: &graphTableColumnCollections)
        }

        private mutating func popMatchPattern() throws(DatabaseWireError) -> MatchPattern {
            guard let value = matchPatterns.popLast() else {
                throw .invalidQueryIRWireState
            }
            return value
        }

        private mutating func popPathPattern() throws(DatabaseWireError) -> PathPattern {
            guard let value = pathPatterns.popLast() else {
                throw .invalidQueryIRWireState
            }
            return value
        }

        private mutating func popPathPatternCollection(
        ) throws(DatabaseWireError) -> [PathPattern] {
            try Self.popLast(from: &pathPatternCollections)
        }

        private mutating func popPathElement(
        ) throws(DatabaseWireError) -> PathElement {
            try Self.popLast(from: &pathElements)
        }

        private mutating func popPathElementCollection(
        ) throws(DatabaseWireError) -> [PathElement] {
            try Self.popLast(from: &pathElementCollections)
        }

        private mutating func popPropertyBinding(
        ) throws(DatabaseWireError) -> PropertyBinding {
            try Self.popLast(from: &propertyBindings)
        }

        private mutating func popPropertyBindingCollection(
        ) throws(DatabaseWireError) -> [PropertyBinding] {
            try Self.popLast(from: &propertyBindingCollections)
        }

        private mutating func popNodePattern() throws(DatabaseWireError) -> NodePattern {
            guard let value = nodePatterns.popLast() else {
                throw .invalidQueryIRWireState
            }
            return value
        }

        private mutating func popEdgePattern() throws(DatabaseWireError) -> EdgePattern {
            guard let value = edgePatterns.popLast() else {
                throw .invalidQueryIRWireState
            }
            return value
        }

        private mutating func ensureQueryStacksAreEmpty() throws(DatabaseWireError) {
            guard expressions.isEmpty,
                  sortKeys.isEmpty,
                  selectQueries.isEmpty,
                  dataSources.isEmpty,
                  graphPatterns.isEmpty,
                  projections.isEmpty,
                  projectionItems.isEmpty,
                  namedSubqueries.isEmpty,
                  aggregateBindings.isEmpty,
                  graphTableSources.isEmpty,
                  graphTableColumns.isEmpty,
                  matchPatterns.isEmpty,
                  pathPatterns.isEmpty,
                  pathElements.isEmpty,
                  propertyBindings.isEmpty,
                  nodePatterns.isEmpty,
                  edgePatterns.isEmpty,
                  expressionCollections.isEmpty,
                  sortKeyCollections.isEmpty,
                  projectionItemCollections.isEmpty,
                  namedSubqueryCollections.isEmpty,
                  dataSourceCollections.isEmpty,
                  aggregateBindingCollections.isEmpty,
                  graphTableColumnCollections.isEmpty,
                  pathPatternCollections.isEmpty,
                  pathElementCollections.isEmpty,
                  propertyBindingCollections.isEmpty else {
                throw .invalidQueryIRWireState
            }
        }

        private static func popLast<Element>(
            from values: inout [Element]
        ) throws(DatabaseWireError) -> Element {
            guard let value = values.popLast() else {
                throw .invalidQueryIRWireState
            }
            return value
        }

        private func decodeJoinType(
            reader: inout DatabaseWireReader
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

        private func decodeEdgeDirection(
            reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> EdgeDirection {
            switch try reader.readUInt8() {
            case 0: return .outgoing
            case 1: return .incoming
            case 2: return .undirected
            case 3: return .any
            case let tag: throw .invalidValueTag(tag)
            }
        }

        private func decodePathQuantifier(
            reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> PathQuantifier {
            switch try reader.readUInt8() {
            case 0:
                return .exactly(try QueryIRWireFormat.readInt(from: &reader))
            case 1:
                return .range(
                    min: try QueryIRWireFormat.readOptionalInt(from: &reader),
                    max: try QueryIRWireFormat.readOptionalInt(from: &reader)
                )
            case 2: return .zeroOrMore
            case 3: return .oneOrMore
            case 4: return .zeroOrOne
            case let tag: throw .invalidValueTag(tag)
            }
        }

        private func decodePathMode(
            reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> PathMode {
            switch try reader.readUInt8() {
            case 0: return .walk
            case 1: return .trail
            case 2: return .acyclic
            case 3: return .simple
            case 4: return .anyShortest
            case 5: return .allShortest
            case 6:
                return .shortestK(try QueryIRWireFormat.readInt(from: &reader))
            case let tag: throw .invalidValueTag(tag)
            }
        }
    }

    static func unary(_ kind: UnaryKind, value: Expression) -> Expression {
        switch kind {
        case .negate: .negate(value)
        case .not: .not(value)
        case .isNull: .isNull(value)
        case .isNotNull: .isNotNull(value)
        case .isTriple: .isTriple(value)
        case .subject: .subject(value)
        case .predicate: .predicate(value)
        case .object: .object(value)
        }
    }

    static func binary(
        _ kind: BinaryKind,
        lhs: Expression,
        rhs: Expression
    ) -> Expression {
        switch kind {
        case .add: .add(lhs, rhs)
        case .subtract: .subtract(lhs, rhs)
        case .multiply: .multiply(lhs, rhs)
        case .divide: .divide(lhs, rhs)
        case .modulo: .modulo(lhs, rhs)
        case .equal: .equal(lhs, rhs)
        case .notEqual: .notEqual(lhs, rhs)
        case .lessThan: .lessThan(lhs, rhs)
        case .lessThanOrEqual: .lessThanOrEqual(lhs, rhs)
        case .greaterThan: .greaterThan(lhs, rhs)
        case .greaterThanOrEqual: .greaterThanOrEqual(lhs, rhs)
        case .and: .and(lhs, rhs)
        case .or: .or(lhs, rhs)
        case .nullIf: .nullIf(lhs, rhs)
        }
    }

    static func aggregateExpression(
        _ kind: AggregateExpressionKind,
        value: Expression,
        distinct: Bool
    ) -> AggregateFunction {
        switch kind {
        case .sum: .sum(value, distinct: distinct)
        case .average: .avg(value, distinct: distinct)
        case .minimum: .min(value)
        case .maximum: .max(value)
        case .sample: .sample(value)
        }
    }
}
