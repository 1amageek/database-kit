import DatabaseTypes
import DatabaseValue

/// Rewrites parameterized QueryIR with an explicit binding traversal stack.
///
/// Structural admission runs before this traversal. The traversal still avoids
/// process-stack recursion so an admitted query cannot exhaust the stack.
/// Unchanged subtrees retain their original copy-on-write storage.
struct QueryParameterBindingTraversal {
    private let positions: [UInt32: FieldValue]
    private let names: [String: FieldValue]
    private var bindingSteps: [BindingStep] = []
    private var results: [BindingResult] = []

    init(
        positions: [UInt32: FieldValue],
        names: [String: FieldValue]
    ) {
        self.positions = positions
        self.names = names
    }

    mutating func bind(
        _ statement: QueryStatement
    ) throws(QueryParameterBindingError) -> QueryStatement {
        bindingSteps.append(.statement(statement))
        while let bindingStep = bindingSteps.popLast() {
            try apply(bindingStep)
        }

        guard results.count == 1 else {
            throw .invalidTraversalState
        }
        return try popStatement().value
    }
}
private extension QueryParameterBindingTraversal {
    struct Bound<Value> {
        let value: Value
        let changed: Bool
    }

    enum BindingStep {
        case statement(QueryStatement)
        case assembleStatement(QueryStatement)
        case select(SelectQuery)
        case assembleSelect(SelectQuery)
        case source(DataSource)
        case assembleSource(DataSource)
        case matchPattern(MatchPattern)
        case assembleMatchPattern(MatchPattern)
        case pathPattern(PathPattern)
        case assemblePathPattern(PathPattern)
        case pathElement(PathElement)
        case assemblePathElement(PathElement)
        case graphPattern(GraphPattern)
        case assembleGraphPattern(GraphPattern)
        case expression(Expression)
        case assembleExpression(Expression)
        case aggregate(AggregateFunction)
        case assembleAggregate(AggregateFunction)
        case modifiers(SPARQLSolutionModifiers)
        case assembleModifiers(SPARQLSolutionModifiers)
        case updateRequest(SPARQLUpdateRequest)
        case assembleUpdateRequest(SPARQLUpdateRequest)
        case updateOperation(SPARQLUpdateOperation)
        case assembleUpdateOperation(SPARQLUpdateOperation)
    }

    enum BindingResult {
        case statement(Bound<QueryStatement>)
        case select(Bound<SelectQuery>)
        case source(Bound<DataSource>)
        case matchPattern(Bound<MatchPattern>)
        case pathPattern(Bound<PathPattern>)
        case pathElement(Bound<PathElement>)
        case graphPattern(Bound<GraphPattern>)
        case expression(Bound<Expression>)
        case aggregate(Bound<AggregateFunction>)
        case modifiers(Bound<SPARQLSolutionModifiers>)
        case updateRequest(Bound<SPARQLUpdateRequest>)
        case updateOperation(Bound<SPARQLUpdateOperation>)
    }

    mutating func apply(
        _ bindingStep: BindingStep
    ) throws(QueryParameterBindingError) {
        switch bindingStep {
        case .statement(let statement):
            enqueueBindings(statement)
        case .assembleStatement(let statement):
            try assemble(statement)
        case .select(let query):
            enqueueBindings(query)
        case .assembleSelect(let query):
            try assemble(query)
        case .source(let source):
            enqueueBindings(source)
        case .assembleSource(let source):
            try assemble(source)
        case .matchPattern(let pattern):
            enqueueBindings(pattern)
        case .assembleMatchPattern(let pattern):
            try assemble(pattern)
        case .pathPattern(let pattern):
            enqueueBindings(pattern)
        case .assemblePathPattern(let pattern):
            try assemble(pattern)
        case .pathElement(let element):
            enqueueBindings(element)
        case .assemblePathElement(let element):
            try assemble(element)
        case .graphPattern(let pattern):
            enqueueBindings(pattern)
        case .assembleGraphPattern(let pattern):
            try assemble(pattern)
        case .expression(let expression):
            try enqueueBindings(expression)
        case .assembleExpression(let expression):
            try assemble(expression)
        case .aggregate(let aggregate):
            enqueueBindings(aggregate)
        case .assembleAggregate(let aggregate):
            try assemble(aggregate)
        case .modifiers(let modifiers):
            enqueueBindings(modifiers)
        case .assembleModifiers(let modifiers):
            try assemble(modifiers)
        case .updateRequest(let request):
            enqueueBindings(request)
        case .assembleUpdateRequest(let request):
            try assemble(request)
        case .updateOperation(let operation):
            enqueueBindings(operation)
        case .assembleUpdateOperation(let operation):
            try assemble(operation)
        }
    }
}

// MARK: - Scheduling

private extension QueryParameterBindingTraversal {
    mutating func enqueueBindings(
        _ statement: QueryStatement
    ) {
        switch statement {
        case .createGraph, .dropGraph:
            results.append(.statement(Bound(value: statement, changed: false)))
        case .select(let query):
            bindingSteps.append(.assembleStatement(statement))
            bindingSteps.append(.select(query))
        case .insert(let query):
            bindingSteps.append(.assembleStatement(statement))
            enqueueProjectionItemBindings(query.returning)
            enqueueConflictActionBindings(query.onConflict)
            enqueueBindings(query.source)
        case .update(let query):
            bindingSteps.append(.assembleStatement(statement))
            enqueueProjectionItemBindings(query.returning)
            if let filter = query.filter {
                bindingSteps.append(.expression(filter))
            }
            if let source = query.from {
                bindingSteps.append(.source(source))
            }
            enqueueAssignmentBindings(query.assignments)
        case .delete(let query):
            bindingSteps.append(.assembleStatement(statement))
            enqueueProjectionItemBindings(query.returning)
            if let filter = query.filter {
                bindingSteps.append(.expression(filter))
            }
            if let source = query.using {
                bindingSteps.append(.source(source))
            }
        case .sparqlUpdate(let request):
            bindingSteps.append(.assembleStatement(statement))
            bindingSteps.append(.updateRequest(request))
        case .construct(let query):
            bindingSteps.append(.assembleStatement(statement))
            bindingSteps.append(.modifiers(query.modifiers))
            bindingSteps.append(.graphPattern(query.pattern))
        case .ask(let query):
            bindingSteps.append(.assembleStatement(statement))
            bindingSteps.append(.modifiers(query.modifiers))
            bindingSteps.append(.graphPattern(query.pattern))
        case .describe(let query):
            bindingSteps.append(.assembleStatement(statement))
            bindingSteps.append(.modifiers(query.modifiers))
            if let pattern = query.pattern {
                bindingSteps.append(.graphPattern(pattern))
            }
        }
    }

    mutating func enqueueBindings(
        _ source: InsertSource
    ) {
        switch source {
        case .values(let rows):
            enqueueExpressionRowBindings(rows)
        case .select(let query):
            bindingSteps.append(.select(query))
        case .defaultValues:
            break
        }
    }

    mutating func enqueueConflictActionBindings(
        _ action: OnConflictAction?
    ) {
        guard case .doUpdate(let assignments, let predicate) = action else {
            return
        }
        if let predicate {
            bindingSteps.append(.expression(predicate))
        }
        enqueueAssignmentBindings(assignments)
    }

    mutating func enqueueBindings(
        _ query: SelectQuery
    ) {
        bindingSteps.append(.assembleSelect(query))
        if let subqueries = query.subqueries {
            for subquery in subqueries.reversed() {
                bindingSteps.append(.select(subquery.query))
            }
        }
        if let orderBy = query.orderBy {
            enqueueSortKeyBindings(orderBy)
        }
        if let having = query.having {
            bindingSteps.append(.expression(having))
        }
        if let groupBy = query.groupBy {
            enqueueExpressionBindings(groupBy)
        }
        if let filter = query.filter {
            bindingSteps.append(.expression(filter))
        }
        bindingSteps.append(.source(query.source))
        enqueueProjectionBindings(query.projection)
    }

    mutating func enqueueBindings(
        _ source: DataSource
    ) {
        switch source {
        case .table, .logical, .values:
            results.append(.source(Bound(value: source, changed: false)))
        case .subquery(let query, _):
            bindingSteps.append(.assembleSource(source))
            bindingSteps.append(.select(query))
        case .join(let join):
            bindingSteps.append(.assembleSource(source))
            if case .on(let expression) = join.condition {
                bindingSteps.append(.expression(expression))
            }
            bindingSteps.append(.source(join.right))
            bindingSteps.append(.source(join.left))
        case .graphTable(let table):
            bindingSteps.append(.assembleSource(source))
            if let columns = table.columns {
                for column in columns.reversed() {
                    bindingSteps.append(.expression(column.expression))
                }
            }
            bindingSteps.append(.matchPattern(table.matchPattern))
        case .graphPattern(let pattern),
             .namedGraph(_, let pattern),
             .service(_, let pattern, _):
            bindingSteps.append(.assembleSource(source))
            bindingSteps.append(.graphPattern(pattern))
        case .union(let sources),
             .unionAll(let sources),
             .intersect(let sources):
            bindingSteps.append(.assembleSource(source))
            enqueueSourceBindings(sources)
        case .except(let lhs, let rhs):
            bindingSteps.append(.assembleSource(source))
            bindingSteps.append(.source(rhs))
            bindingSteps.append(.source(lhs))
        }
    }

    mutating func enqueueBindings(
        _ pattern: MatchPattern
    ) {
        bindingSteps.append(.assembleMatchPattern(pattern))
        if let predicate = pattern.where {
            bindingSteps.append(.expression(predicate))
        }
        for path in pattern.paths.reversed() {
            bindingSteps.append(.pathPattern(path))
        }
    }

    mutating func enqueueBindings(
        _ pattern: PathPattern
    ) {
        bindingSteps.append(.assemblePathPattern(pattern))
        for element in pattern.elements.reversed() {
            bindingSteps.append(.pathElement(element))
        }
    }

    mutating func enqueueBindings(
        _ element: PathElement
    ) {
        switch element {
        case .node(let node):
            guard let properties = node.properties else {
                results.append(.pathElement(Bound(value: element, changed: false)))
                return
            }
            bindingSteps.append(.assemblePathElement(element))
            enqueuePropertyValueBindings(properties)
        case .edge(let edge):
            guard let properties = edge.properties else {
                results.append(.pathElement(Bound(value: element, changed: false)))
                return
            }
            bindingSteps.append(.assemblePathElement(element))
            enqueuePropertyValueBindings(properties)
        case .quantified(let pattern, _):
            bindingSteps.append(.assemblePathElement(element))
            bindingSteps.append(.pathPattern(pattern))
        case .alternation(let alternatives):
            bindingSteps.append(.assemblePathElement(element))
            for alternative in alternatives.reversed() {
                bindingSteps.append(.pathPattern(alternative))
            }
        }
    }

    mutating func enqueueBindings(
        _ pattern: GraphPattern
    ) {
        switch pattern {
        case .basic, .values:
            results.append(.graphPattern(Bound(value: pattern, changed: false)))
        case .join(let lhs, let rhs),
             .optional(let lhs, let rhs),
             .union(let lhs, let rhs),
             .minus(let lhs, let rhs),
             .lateral(let lhs, let rhs):
            bindingSteps.append(.assembleGraphPattern(pattern))
            bindingSteps.append(.graphPattern(rhs))
            bindingSteps.append(.graphPattern(lhs))
        case .filter(let nested, let expression):
            bindingSteps.append(.assembleGraphPattern(pattern))
            bindingSteps.append(.expression(expression))
            bindingSteps.append(.graphPattern(nested))
        case .graph(_, let nested), .service(_, let nested, _):
            bindingSteps.append(.assembleGraphPattern(pattern))
            bindingSteps.append(.graphPattern(nested))
        case .bind(let nested, _, let expression):
            bindingSteps.append(.assembleGraphPattern(pattern))
            bindingSteps.append(.expression(expression))
            bindingSteps.append(.graphPattern(nested))
        case .subquery(let query):
            bindingSteps.append(.assembleGraphPattern(pattern))
            bindingSteps.append(.select(query))
        case .groupBy(let nested, let expressions, let aggregates):
            bindingSteps.append(.assembleGraphPattern(pattern))
            for aggregate in aggregates.reversed() {
                bindingSteps.append(.aggregate(aggregate.aggregate))
            }
            enqueueExpressionBindings(expressions)
            bindingSteps.append(.graphPattern(nested))
        }
    }

    mutating func enqueueBindings(
        _ expression: Expression
    ) throws(QueryParameterBindingError) {
        switch expression {
        case .literal, .column, .variable, .bound:
            results.append(.expression(Bound(value: expression, changed: false)))
        case .parameter(let reference):
            results.append(
                .expression(
                    Bound(
                        value: .literal(try literal(for: reference)),
                        changed: true
                    )
                )
            )
        case .add(let lhs, let rhs),
             .subtract(let lhs, let rhs),
             .multiply(let lhs, let rhs),
             .divide(let lhs, let rhs),
             .modulo(let lhs, let rhs),
             .equal(let lhs, let rhs),
             .notEqual(let lhs, let rhs),
             .lessThan(let lhs, let rhs),
             .lessThanOrEqual(let lhs, let rhs),
             .greaterThan(let lhs, let rhs),
             .greaterThanOrEqual(let lhs, let rhs),
             .and(let lhs, let rhs),
             .or(let lhs, let rhs),
             .nullIf(let lhs, let rhs):
            bindingSteps.append(.assembleExpression(expression))
            bindingSteps.append(.expression(rhs))
            bindingSteps.append(.expression(lhs))
        case .negate(let value),
             .not(let value),
             .isNull(let value),
             .isNotNull(let value),
             .like(let value, _),
             .regex(let value, _, _),
             .cast(let value, _),
             .isTriple(let value),
             .subject(let value),
             .predicate(let value),
             .object(let value):
            bindingSteps.append(.assembleExpression(expression))
            bindingSteps.append(.expression(value))
        case .between(let value, let low, let high):
            bindingSteps.append(.assembleExpression(expression))
            bindingSteps.append(.expression(high))
            bindingSteps.append(.expression(low))
            bindingSteps.append(.expression(value))
        case .inList(let value, let values),
             .notInList(let value, let values):
            bindingSteps.append(.assembleExpression(expression))
            enqueueExpressionBindings(values)
            bindingSteps.append(.expression(value))
        case .inSubquery(let value, let query):
            bindingSteps.append(.assembleExpression(expression))
            bindingSteps.append(.select(query))
            bindingSteps.append(.expression(value))
        case .aggregate(let aggregate):
            bindingSteps.append(.assembleExpression(expression))
            bindingSteps.append(.aggregate(aggregate))
        case .function(let function):
            bindingSteps.append(.assembleExpression(expression))
            enqueueExpressionBindings(function.arguments)
        case .caseWhen(let cases, let elseResult):
            bindingSteps.append(.assembleExpression(expression))
            if let elseResult {
                bindingSteps.append(.expression(elseResult))
            }
            for pair in cases.reversed() {
                bindingSteps.append(.expression(pair.result))
                bindingSteps.append(.expression(pair.condition))
            }
        case .coalesce(let values):
            bindingSteps.append(.assembleExpression(expression))
            enqueueExpressionBindings(values)
        case .triple(let subject, let predicate, let object):
            bindingSteps.append(.assembleExpression(expression))
            bindingSteps.append(.expression(object))
            bindingSteps.append(.expression(predicate))
            bindingSteps.append(.expression(subject))
        case .subquery(let query), .exists(let query):
            bindingSteps.append(.assembleExpression(expression))
            bindingSteps.append(.select(query))
        }
    }

    mutating func enqueueBindings(
        _ aggregate: AggregateFunction
    ) {
        switch aggregate {
        case .count(.none, _):
            results.append(.aggregate(Bound(value: aggregate, changed: false)))
        case .count(.some(let expression), _),
             .sum(let expression, _),
             .avg(let expression, _),
             .min(let expression),
             .max(let expression),
             .groupConcat(let expression, _, _),
             .sample(let expression):
            bindingSteps.append(.assembleAggregate(aggregate))
            bindingSteps.append(.expression(expression))
        case .arrayAgg(let expression, let orderBy, _):
            bindingSteps.append(.assembleAggregate(aggregate))
            if let orderBy {
                enqueueSortKeyBindings(orderBy)
            }
            bindingSteps.append(.expression(expression))
        }
    }

    mutating func enqueueBindings(
        _ modifiers: SPARQLSolutionModifiers
    ) {
        bindingSteps.append(.assembleModifiers(modifiers))
        enqueueSortKeyBindings(modifiers.orderBy)
        enqueueExpressionBindings(modifiers.having)
        enqueueExpressionBindings(modifiers.groupBy)
    }

    mutating func enqueueBindings(
        _ request: SPARQLUpdateRequest
    ) {
        bindingSteps.append(.assembleUpdateRequest(request))
        for operation in request.additionalOperations.reversed() {
            bindingSteps.append(.updateOperation(operation))
        }
        bindingSteps.append(.updateOperation(request.firstOperation))
    }

    mutating func enqueueBindings(
        _ operation: SPARQLUpdateOperation
    ) {
        guard case .modify(let query) = operation else {
            results.append(.updateOperation(Bound(value: operation, changed: false)))
            return
        }
        bindingSteps.append(.assembleUpdateOperation(operation))
        bindingSteps.append(.graphPattern(query.wherePattern))
    }

    mutating func enqueueProjectionBindings(
        _ projection: Projection
    ) {
        switch projection {
        case .all, .allFrom:
            break
        case .items(let items), .distinctItems(let items):
            enqueueProjectionItemBindings(items)
        }
    }

    mutating func enqueueProjectionItemBindings(
        _ items: [ProjectionItem]?
    ) {
        guard let items else {
            return
        }
        for projectionItem in items.reversed() {
            bindingSteps.append(.expression(projectionItem.expression))
        }
    }

    mutating func enqueueAssignmentBindings(
        _ assignments: [Assignment]
    ) {
        for assignment in assignments.reversed() {
            bindingSteps.append(.expression(assignment.value))
        }
    }

    mutating func enqueuePropertyValueBindings(
        _ properties: [PropertyBinding]
    ) {
        for property in properties.reversed() {
            bindingSteps.append(.expression(property.value))
        }
    }

    mutating func enqueueSortKeyBindings(
        _ sortKeys: [SortKey]
    ) {
        for sortKey in sortKeys.reversed() {
            bindingSteps.append(.expression(sortKey.expression))
        }
    }

    mutating func enqueueExpressionBindings(
        _ expressions: [Expression]
    ) {
        for expression in expressions.reversed() {
            bindingSteps.append(.expression(expression))
        }
    }

    mutating func enqueueExpressionRowBindings(
        _ rows: [[Expression]]
    ) {
        for row in rows.reversed() {
            enqueueExpressionBindings(row)
        }
    }

    mutating func enqueueSourceBindings(
        _ sources: [DataSource]
    ) {
        for source in sources.reversed() {
            bindingSteps.append(.source(source))
        }
    }
}

// MARK: - Assembly

private extension QueryParameterBindingTraversal {
    mutating func assemble(
        _ statement: QueryStatement
    ) throws(QueryParameterBindingError) {
        let bound: Bound<QueryStatement>
        switch statement {
        case .select:
            let query = try popSelect()
            bound = Bound(
                value: query.changed ? .select(query.value) : statement,
                changed: query.changed
            )
        case .insert(let query):
            bound = try assembleInsert(query, original: statement)
        case .update(let query):
            bound = try assembleUpdate(query, original: statement)
        case .delete(let query):
            bound = try assembleDelete(query, original: statement)
        case .sparqlUpdate:
            let request = try popUpdateRequest()
            bound = Bound(
                value: request.changed ? .sparqlUpdate(request.value) : statement,
                changed: request.changed
            )
        case .construct(let query):
            let modifiers = try popModifiers()
            let pattern = try popGraphPattern()
            let changed = modifiers.changed || pattern.changed
            bound = Bound(
                value: changed
                    ? .construct(
                        ConstructQuery(
                            template: query.template,
                            pattern: pattern.value,
                            dataset: query.dataset,
                            modifiers: modifiers.value
                        )
                    )
                    : statement,
                changed: changed
            )
        case .ask(let query):
            let modifiers = try popModifiers()
            let pattern = try popGraphPattern()
            let changed = modifiers.changed || pattern.changed
            bound = Bound(
                value: changed
                    ? .ask(
                        AskQuery(
                            pattern: pattern.value,
                            dataset: query.dataset,
                            modifiers: modifiers.value
                        )
                    )
                    : statement,
                changed: changed
            )
        case .describe(let query):
            let modifiers = try popModifiers()
            let pattern = try popOptionalGraphPattern(query.pattern)
            let changed = modifiers.changed || pattern.changed
            bound = Bound(
                value: changed
                    ? .describe(
                        DescribeQuery(
                            selection: query.selection,
                            pattern: pattern.value,
                            dataset: query.dataset,
                            modifiers: modifiers.value
                        )
                    )
                    : statement,
                changed: changed
            )
        case .createGraph, .dropGraph:
            throw .invalidTraversalState
        }
        results.append(.statement(bound))
    }

    mutating func assembleInsert(
        _ query: InsertQuery,
        original: QueryStatement
    ) throws(QueryParameterBindingError) -> Bound<QueryStatement> {
        let returning = try popOptionalProjectionItems(query.returning)
        let conflict = try popConflictAction(query.onConflict)
        let source = try popInsertSource(query.source)
        let changed = returning.changed || conflict.changed || source.changed
        guard changed else {
            return Bound(value: original, changed: false)
        }
        return Bound(
            value: .insert(
                InsertQuery(
                    target: query.target,
                    columns: query.columns,
                    source: source.value,
                    onConflict: conflict.value,
                    returning: returning.value
                )
            ),
            changed: true
        )
    }

    mutating func assembleUpdate(
        _ query: UpdateQuery,
        original: QueryStatement
    ) throws(QueryParameterBindingError) -> Bound<QueryStatement> {
        let returning = try popOptionalProjectionItems(query.returning)
        let filter = try popOptionalExpression(query.filter)
        let source = try popOptionalSource(query.from)
        let assignments = try popAssignments(query.assignments)
        let changed = returning.changed || filter.changed || source.changed
            || assignments.changed
        guard changed else {
            return Bound(value: original, changed: false)
        }
        return Bound(
            value: .update(
                UpdateQuery(
                    target: query.target,
                    assignments: assignments.value,
                    from: source.value,
                    filter: filter.value,
                    returning: returning.value
                )
            ),
            changed: true
        )
    }

    mutating func assembleDelete(
        _ query: DeleteQuery,
        original: QueryStatement
    ) throws(QueryParameterBindingError) -> Bound<QueryStatement> {
        let returning = try popOptionalProjectionItems(query.returning)
        let filter = try popOptionalExpression(query.filter)
        let source = try popOptionalSource(query.using)
        let changed = returning.changed || filter.changed || source.changed
        guard changed else {
            return Bound(value: original, changed: false)
        }
        return Bound(
            value: .delete(
                DeleteQuery(
                    target: query.target,
                    using: source.value,
                    filter: filter.value,
                    returning: returning.value
                )
            ),
            changed: true
        )
    }

    mutating func assemble(
        _ query: SelectQuery
    ) throws(QueryParameterBindingError) {
        let subqueries = try popOptionalNamedSubqueries(query.subqueries)
        let orderBy = try popOptionalSortKeys(query.orderBy)
        let having = try popOptionalExpression(query.having)
        let groupBy = try popOptionalExpressions(query.groupBy)
        let filter = try popOptionalExpression(query.filter)
        let source = try popSource()
        let projection = try popProjection(query.projection)
        let changed = subqueries.changed || orderBy.changed || having.changed
            || groupBy.changed || filter.changed || source.changed
            || projection.changed

        guard changed else {
            results.append(.select(Bound(value: query, changed: false)))
            return
        }
        results.append(
            .select(
                Bound(
                    value: SelectQuery(
                        projection: projection.value,
                        source: source.value,
                        accessPath: query.accessPath,
                        filter: filter.value,
                        groupBy: groupBy.value,
                        having: having.value,
                        orderBy: orderBy.value,
                        limit: query.limit,
                        offset: query.offset,
                        distinct: query.distinct,
                        subqueries: subqueries.value,
                        reduced: query.reduced,
                        dataset: query.dataset
                    ),
                    changed: true
                )
            )
        )
    }

    mutating func assemble(
        _ source: DataSource
    ) throws(QueryParameterBindingError) {
        let bound: Bound<DataSource>
        switch source {
        case .subquery(_, let alias):
            let child = try popSelect()
            bound = Bound(
                value: child.changed
                    ? .subquery(child.value, alias: alias)
                    : source,
                changed: child.changed
            )
        case .join(let join):
            let condition = try popJoinCondition(join.condition)
            let right = try popSource()
            let left = try popSource()
            let changed = condition.changed || left.changed || right.changed
            bound = Bound(
                value: changed
                    ? .join(
                        JoinClause(
                            type: join.type,
                            left: left.value,
                            right: right.value,
                            condition: condition.value
                        )
                    )
                    : source,
                changed: changed
            )
        case .graphTable(let table):
            let columns = try popOptionalGraphTableColumns(table.columns)
            let pattern = try popMatchPattern()
            let changed = columns.changed || pattern.changed
            bound = Bound(
                value: changed
                    ? .graphTable(
                        GraphTableSource(
                            graphName: table.graphName,
                            matchPattern: pattern.value,
                            columns: columns.value,
                            alias: table.alias
                        )
                    )
                    : source,
                changed: changed
            )
        case .graphPattern:
            let pattern = try popGraphPattern()
            bound = Bound(
                value: pattern.changed ? .graphPattern(pattern.value) : source,
                changed: pattern.changed
            )
        case .namedGraph(let name, _):
            let pattern = try popGraphPattern()
            bound = Bound(
                value: pattern.changed
                    ? .namedGraph(name: name, pattern: pattern.value)
                    : source,
                changed: pattern.changed
            )
        case .service(let endpoint, _, let silent):
            let pattern = try popGraphPattern()
            bound = Bound(
                value: pattern.changed
                    ? .service(
                        endpoint: endpoint,
                        pattern: pattern.value,
                        silent: silent
                    )
                    : source,
                changed: pattern.changed
            )
        case .union(let sources):
            let children = try popSources(sources)
            bound = Bound(
                value: children.changed ? .union(children.value) : source,
                changed: children.changed
            )
        case .unionAll(let sources):
            let children = try popSources(sources)
            bound = Bound(
                value: children.changed ? .unionAll(children.value) : source,
                changed: children.changed
            )
        case .intersect(let sources):
            let children = try popSources(sources)
            bound = Bound(
                value: children.changed ? .intersect(children.value) : source,
                changed: children.changed
            )
        case .except:
            let right = try popSource()
            let left = try popSource()
            let changed = left.changed || right.changed
            bound = Bound(
                value: changed ? .except(left.value, right.value) : source,
                changed: changed
            )
        case .table, .logical, .values:
            throw .invalidTraversalState
        }
        results.append(.source(bound))
    }

    mutating func assemble(
        _ pattern: MatchPattern
    ) throws(QueryParameterBindingError) {
        let predicate = try popOptionalExpression(pattern.where)
        let paths = try popPathPatterns(pattern.paths)
        let changed = predicate.changed || paths.changed
        results.append(
            .matchPattern(
                Bound(
                    value: changed
                        ? MatchPattern(paths: paths.value, where: predicate.value)
                        : pattern,
                    changed: changed
                )
            )
        )
    }

    mutating func assemble(
        _ pattern: PathPattern
    ) throws(QueryParameterBindingError) {
        let elements = try popPathElements(pattern.elements)
        results.append(
            .pathPattern(
                Bound(
                    value: elements.changed
                        ? PathPattern(
                            pathVariable: pattern.pathVariable,
                            elements: elements.value,
                            mode: pattern.mode
                        )
                        : pattern,
                    changed: elements.changed
                )
            )
        )
    }

    mutating func assemble(
        _ element: PathElement
    ) throws(QueryParameterBindingError) {
        let bound: Bound<PathElement>
        switch element {
        case .node(let node):
            let properties = try popOptionalPropertyBindings(node.properties)
            bound = Bound(
                value: properties.changed
                    ? .node(
                        NodePattern(
                            variable: node.variable,
                            labels: node.labels,
                            properties: properties.value
                        )
                    )
                    : element,
                changed: properties.changed
            )
        case .edge(let edge):
            let properties = try popOptionalPropertyBindings(edge.properties)
            bound = Bound(
                value: properties.changed
                    ? .edge(
                        EdgePattern(
                            variable: edge.variable,
                            labels: edge.labels,
                            properties: properties.value,
                            direction: edge.direction
                        )
                    )
                    : element,
                changed: properties.changed
            )
        case .quantified(_, let quantifier):
            let pattern = try popPathPattern()
            bound = Bound(
                value: pattern.changed
                    ? .quantified(pattern.value, quantifier: quantifier)
                    : element,
                changed: pattern.changed
            )
        case .alternation(let alternatives):
            let patterns = try popPathPatterns(alternatives)
            bound = Bound(
                value: patterns.changed ? .alternation(patterns.value) : element,
                changed: patterns.changed
            )
        }
        results.append(.pathElement(bound))
    }

    mutating func assemble(
        _ pattern: GraphPattern
    ) throws(QueryParameterBindingError) {
        let bound: Bound<GraphPattern>
        switch pattern {
        case .join:
            bound = try popBinaryGraphPattern(original: pattern) { .join($0, $1) }
        case .optional:
            bound = try popBinaryGraphPattern(original: pattern) { .optional($0, $1) }
        case .union:
            bound = try popBinaryGraphPattern(original: pattern) { .union($0, $1) }
        case .minus:
            bound = try popBinaryGraphPattern(original: pattern) { .minus($0, $1) }
        case .lateral:
            bound = try popBinaryGraphPattern(original: pattern) { .lateral($0, $1) }
        case .filter:
            let expression = try popExpression()
            let nested = try popGraphPattern()
            let changed = nested.changed || expression.changed
            bound = Bound(
                value: changed
                    ? .filter(nested.value, expression.value)
                    : pattern,
                changed: changed
            )
        case .graph(let name, _):
            let nested = try popGraphPattern()
            bound = Bound(
                value: nested.changed
                    ? .graph(name: name, pattern: nested.value)
                    : pattern,
                changed: nested.changed
            )
        case .service(let endpoint, _, let silent):
            let nested = try popGraphPattern()
            bound = Bound(
                value: nested.changed
                    ? .service(
                        endpoint: endpoint,
                        pattern: nested.value,
                        silent: silent
                    )
                    : pattern,
                changed: nested.changed
            )
        case .bind(_, let variable, _):
            let expression = try popExpression()
            let nested = try popGraphPattern()
            let changed = nested.changed || expression.changed
            bound = Bound(
                value: changed
                    ? .bind(
                        nested.value,
                        variable: variable,
                        expression: expression.value
                    )
                    : pattern,
                changed: changed
            )
        case .subquery:
            let query = try popSelect()
            bound = Bound(
                value: query.changed ? .subquery(query.value) : pattern,
                changed: query.changed
            )
        case .groupBy(_, let expressions, let aggregates):
            let boundAggregates = try popAggregateBindings(aggregates)
            let boundExpressions = try popExpressions(expressions)
            let nested = try popGraphPattern()
            let changed = boundAggregates.changed || boundExpressions.changed
                || nested.changed
            bound = Bound(
                value: changed
                    ? .groupBy(
                        nested.value,
                        expressions: boundExpressions.value,
                        aggregates: boundAggregates.value
                    )
                    : pattern,
                changed: changed
            )
        case .basic, .values:
            throw .invalidTraversalState
        }
        results.append(.graphPattern(bound))
    }

    mutating func assemble(
        _ expression: Expression
    ) throws(QueryParameterBindingError) {
        let bound: Bound<Expression>
        switch expression {
        case .add:
            bound = try popBinaryExpression(original: expression) { .add($0, $1) }
        case .subtract:
            bound = try popBinaryExpression(original: expression) { .subtract($0, $1) }
        case .multiply:
            bound = try popBinaryExpression(original: expression) { .multiply($0, $1) }
        case .divide:
            bound = try popBinaryExpression(original: expression) { .divide($0, $1) }
        case .modulo:
            bound = try popBinaryExpression(original: expression) { .modulo($0, $1) }
        case .equal:
            bound = try popBinaryExpression(original: expression) { .equal($0, $1) }
        case .notEqual:
            bound = try popBinaryExpression(original: expression) { .notEqual($0, $1) }
        case .lessThan:
            bound = try popBinaryExpression(original: expression) { .lessThan($0, $1) }
        case .lessThanOrEqual:
            bound = try popBinaryExpression(original: expression) { .lessThanOrEqual($0, $1) }
        case .greaterThan:
            bound = try popBinaryExpression(original: expression) { .greaterThan($0, $1) }
        case .greaterThanOrEqual:
            bound = try popBinaryExpression(original: expression) { .greaterThanOrEqual($0, $1) }
        case .and:
            bound = try popBinaryExpression(original: expression) { .and($0, $1) }
        case .or:
            bound = try popBinaryExpression(original: expression) { .or($0, $1) }
        case .nullIf:
            bound = try popBinaryExpression(original: expression) { .nullIf($0, $1) }
        case .negate:
            bound = try popUnaryExpression(original: expression) { .negate($0) }
        case .not:
            bound = try popUnaryExpression(original: expression) { .not($0) }
        case .isNull:
            bound = try popUnaryExpression(original: expression) { .isNull($0) }
        case .isNotNull:
            bound = try popUnaryExpression(original: expression) { .isNotNull($0) }
        case .like(_, let pattern):
            bound = try popUnaryExpression(original: expression) {
                .like($0, pattern: pattern)
            }
        case .regex(_, let pattern, let flags):
            bound = try popUnaryExpression(original: expression) {
                .regex($0, pattern: pattern, flags: flags)
            }
        case .cast(_, let targetType):
            bound = try popUnaryExpression(original: expression) {
                .cast($0, targetType: targetType)
            }
        case .isTriple:
            bound = try popUnaryExpression(original: expression) { .isTriple($0) }
        case .subject:
            bound = try popUnaryExpression(original: expression) { .subject($0) }
        case .predicate:
            bound = try popUnaryExpression(original: expression) { .predicate($0) }
        case .object:
            bound = try popUnaryExpression(original: expression) { .object($0) }
        case .between:
            let high = try popExpression()
            let low = try popExpression()
            let value = try popExpression()
            let changed = value.changed || low.changed || high.changed
            bound = Bound(
                value: changed
                    ? .between(value.value, low: low.value, high: high.value)
                    : expression,
                changed: changed
            )
        case .inList(_, let values):
            let boundValues = try popExpressions(values)
            let value = try popExpression()
            let changed = value.changed || boundValues.changed
            bound = Bound(
                value: changed
                    ? .inList(value.value, values: boundValues.value)
                    : expression,
                changed: changed
            )
        case .notInList(_, let values):
            let boundValues = try popExpressions(values)
            let value = try popExpression()
            let changed = value.changed || boundValues.changed
            bound = Bound(
                value: changed
                    ? .notInList(value.value, values: boundValues.value)
                    : expression,
                changed: changed
            )
        case .inSubquery:
            let query = try popSelect()
            let value = try popExpression()
            let changed = value.changed || query.changed
            bound = Bound(
                value: changed
                    ? .inSubquery(value.value, subquery: query.value)
                    : expression,
                changed: changed
            )
        case .aggregate:
            let aggregate = try popAggregate()
            bound = Bound(
                value: aggregate.changed
                    ? .aggregate(aggregate.value)
                    : expression,
                changed: aggregate.changed
            )
        case .function(let function):
            let arguments = try popExpressions(function.arguments)
            bound = Bound(
                value: arguments.changed
                    ? .function(
                        FunctionCall(
                            name: function.name,
                            arguments: arguments.value,
                            distinct: function.distinct
                        )
                    )
                    : expression,
                changed: arguments.changed
            )
        case .caseWhen(let cases, let elseResult):
            let boundElse = try popOptionalExpression(elseResult)
            let boundCases = try popCaseWhenPairs(cases)
            let changed = boundElse.changed || boundCases.changed
            bound = Bound(
                value: changed
                    ? .caseWhen(
                        cases: boundCases.value,
                        elseResult: boundElse.value
                    )
                    : expression,
                changed: changed
            )
        case .coalesce(let values):
            let boundValues = try popExpressions(values)
            bound = Bound(
                value: boundValues.changed
                    ? .coalesce(boundValues.value)
                    : expression,
                changed: boundValues.changed
            )
        case .triple:
            let object = try popExpression()
            let predicate = try popExpression()
            let subject = try popExpression()
            let changed = subject.changed || predicate.changed || object.changed
            bound = Bound(
                value: changed
                    ? .triple(
                        subject: subject.value,
                        predicate: predicate.value,
                        object: object.value
                    )
                    : expression,
                changed: changed
            )
        case .subquery:
            let query = try popSelect()
            bound = Bound(
                value: query.changed ? .subquery(query.value) : expression,
                changed: query.changed
            )
        case .exists:
            let query = try popSelect()
            bound = Bound(
                value: query.changed ? .exists(query.value) : expression,
                changed: query.changed
            )
        case .literal, .column, .variable, .parameter, .bound:
            throw .invalidTraversalState
        }
        results.append(.expression(bound))
    }

    mutating func assemble(
        _ aggregate: AggregateFunction
    ) throws(QueryParameterBindingError) {
        let bound: Bound<AggregateFunction>
        switch aggregate {
        case .count(.some, let distinct):
            let expression = try popExpression()
            bound = Bound(
                value: expression.changed
                    ? .count(expression.value, distinct: distinct)
                    : aggregate,
                changed: expression.changed
            )
        case .sum(_, let distinct):
            bound = try popUnaryAggregate(original: aggregate) {
                .sum($0, distinct: distinct)
            }
        case .avg(_, let distinct):
            bound = try popUnaryAggregate(original: aggregate) {
                .avg($0, distinct: distinct)
            }
        case .min:
            bound = try popUnaryAggregate(original: aggregate) { .min($0) }
        case .max:
            bound = try popUnaryAggregate(original: aggregate) { .max($0) }
        case .groupConcat(_, let separator, let distinct):
            bound = try popUnaryAggregate(original: aggregate) {
                .groupConcat($0, separator: separator, distinct: distinct)
            }
        case .sample:
            bound = try popUnaryAggregate(original: aggregate) { .sample($0) }
        case .arrayAgg(_, let orderBy, let distinct):
            let keys = try popOptionalSortKeys(orderBy)
            let expression = try popExpression()
            let changed = expression.changed || keys.changed
            bound = Bound(
                value: changed
                    ? .arrayAgg(
                        expression.value,
                        orderBy: keys.value,
                        distinct: distinct
                    )
                    : aggregate,
                changed: changed
            )
        case .count(.none, _):
            throw .invalidTraversalState
        }
        results.append(.aggregate(bound))
    }

    mutating func assemble(
        _ modifiers: SPARQLSolutionModifiers
    ) throws(QueryParameterBindingError) {
        let orderBy = try popSortKeys(modifiers.orderBy)
        let having = try popExpressions(modifiers.having)
        let groupBy = try popExpressions(modifiers.groupBy)
        let changed = orderBy.changed || having.changed || groupBy.changed
        results.append(
            .modifiers(
                Bound(
                    value: changed
                        ? SPARQLSolutionModifiers(
                            groupBy: groupBy.value,
                            having: having.value,
                            orderBy: orderBy.value,
                            limit: modifiers.limit,
                            offset: modifiers.offset
                        )
                        : modifiers,
                    changed: changed
                )
            )
        )
    }

    mutating func assemble(
        _ request: SPARQLUpdateRequest
    ) throws(QueryParameterBindingError) {
        var additional = request.additionalOperations
        var changed = false
        for index in additional.indices.reversed() {
            let operation = try popUpdateOperation()
            if operation.changed {
                additional[index] = operation.value
                changed = true
            }
        }
        let first = try popUpdateOperation()
        changed = changed || first.changed
        results.append(
            .updateRequest(
                Bound(
                    value: changed
                        ? SPARQLUpdateRequest(
                            firstOperation: first.value,
                            additionalOperations: additional
                        )
                        : request,
                    changed: changed
                )
            )
        )
    }

    mutating func assemble(
        _ operation: SPARQLUpdateOperation
    ) throws(QueryParameterBindingError) {
        guard case .modify(let query) = operation else {
            throw .invalidTraversalState
        }
        let pattern = try popGraphPattern()
        results.append(
            .updateOperation(
                Bound(
                    value: pattern.changed
                        ? .modify(
                            SPARQLModifyOperation(
                                withGraph: query.withGraph,
                                action: query.action,
                                using: query.using,
                                wherePattern: pattern.value
                            )
                        )
                        : operation,
                    changed: pattern.changed
                )
            )
        )
    }
}

// MARK: - Typed Result Stack

private extension QueryParameterBindingTraversal {
    mutating func popStatement() throws(QueryParameterBindingError) -> Bound<QueryStatement> {
        guard case .statement(let value) = results.popLast() else {
            throw .invalidTraversalState
        }
        return value
    }

    mutating func popSelect() throws(QueryParameterBindingError) -> Bound<SelectQuery> {
        guard case .select(let value) = results.popLast() else {
            throw .invalidTraversalState
        }
        return value
    }

    mutating func popSource() throws(QueryParameterBindingError) -> Bound<DataSource> {
        guard case .source(let value) = results.popLast() else {
            throw .invalidTraversalState
        }
        return value
    }

    mutating func popMatchPattern() throws(QueryParameterBindingError) -> Bound<MatchPattern> {
        guard case .matchPattern(let value) = results.popLast() else {
            throw .invalidTraversalState
        }
        return value
    }

    mutating func popPathPattern() throws(QueryParameterBindingError) -> Bound<PathPattern> {
        guard case .pathPattern(let value) = results.popLast() else {
            throw .invalidTraversalState
        }
        return value
    }

    mutating func popPathElement() throws(QueryParameterBindingError) -> Bound<PathElement> {
        guard case .pathElement(let value) = results.popLast() else {
            throw .invalidTraversalState
        }
        return value
    }

    mutating func popGraphPattern() throws(QueryParameterBindingError) -> Bound<GraphPattern> {
        guard case .graphPattern(let value) = results.popLast() else {
            throw .invalidTraversalState
        }
        return value
    }

    mutating func popExpression() throws(QueryParameterBindingError) -> Bound<Expression> {
        guard case .expression(let value) = results.popLast() else {
            throw .invalidTraversalState
        }
        return value
    }

    mutating func popAggregate() throws(QueryParameterBindingError) -> Bound<AggregateFunction> {
        guard case .aggregate(let value) = results.popLast() else {
            throw .invalidTraversalState
        }
        return value
    }

    mutating func popModifiers() throws(QueryParameterBindingError) -> Bound<SPARQLSolutionModifiers> {
        guard case .modifiers(let value) = results.popLast() else {
            throw .invalidTraversalState
        }
        return value
    }

    mutating func popUpdateRequest() throws(QueryParameterBindingError) -> Bound<SPARQLUpdateRequest> {
        guard case .updateRequest(let value) = results.popLast() else {
            throw .invalidTraversalState
        }
        return value
    }

    mutating func popUpdateOperation() throws(QueryParameterBindingError) -> Bound<SPARQLUpdateOperation> {
        guard case .updateOperation(let value) = results.popLast() else {
            throw .invalidTraversalState
        }
        return value
    }

    mutating func popOptionalExpression(
        _ original: Expression?
    ) throws(QueryParameterBindingError) -> Bound<Expression?> {
        guard original != nil else {
            return Bound(value: nil, changed: false)
        }
        let value = try popExpression()
        return Bound(value: value.value, changed: value.changed)
    }

    mutating func popOptionalSource(
        _ original: DataSource?
    ) throws(QueryParameterBindingError) -> Bound<DataSource?> {
        guard original != nil else {
            return Bound(value: nil, changed: false)
        }
        let value = try popSource()
        return Bound(value: value.value, changed: value.changed)
    }

    mutating func popOptionalGraphPattern(
        _ original: GraphPattern?
    ) throws(QueryParameterBindingError) -> Bound<GraphPattern?> {
        guard original != nil else {
            return Bound(value: nil, changed: false)
        }
        let value = try popGraphPattern()
        return Bound(value: value.value, changed: value.changed)
    }

    mutating func popExpressions(
        _ originals: [Expression]
    ) throws(QueryParameterBindingError) -> Bound<[Expression]> {
        var values = originals
        var changed = false
        for index in values.indices.reversed() {
            let value = try popExpression()
            if value.changed {
                values[index] = value.value
                changed = true
            }
        }
        return Bound(value: values, changed: changed)
    }

    mutating func popOptionalExpressions(
        _ originals: [Expression]?
    ) throws(QueryParameterBindingError) -> Bound<[Expression]?> {
        guard let originals else {
            return Bound(value: nil, changed: false)
        }
        let values = try popExpressions(originals)
        return Bound(value: values.value, changed: values.changed)
    }

    mutating func popExpressionRows(
        _ originals: [[Expression]]
    ) throws(QueryParameterBindingError) -> Bound<[[Expression]]> {
        var rows = originals
        var changed = false
        for rowIndex in rows.indices.reversed() {
            let row = try popExpressions(rows[rowIndex])
            if row.changed {
                rows[rowIndex] = row.value
                changed = true
            }
        }
        return Bound(value: rows, changed: changed)
    }

    mutating func popProjection(
        _ projection: Projection
    ) throws(QueryParameterBindingError) -> Bound<Projection> {
        switch projection {
        case .all, .allFrom:
            return Bound(value: projection, changed: false)
        case .items(let items):
            let values = try popProjectionItems(items)
            return Bound(
                value: values.changed ? .items(values.value) : projection,
                changed: values.changed
            )
        case .distinctItems(let items):
            let values = try popProjectionItems(items)
            return Bound(
                value: values.changed ? .distinctItems(values.value) : projection,
                changed: values.changed
            )
        }
    }

    mutating func popProjectionItems(
        _ originals: [ProjectionItem]
    ) throws(QueryParameterBindingError) -> Bound<[ProjectionItem]> {
        var values = originals
        var changed = false
        for index in values.indices.reversed() {
            let expression = try popExpression()
            if expression.changed {
                values[index] = ProjectionItem(
                    expression.value,
                    alias: originals[index].alias
                )
                changed = true
            }
        }
        return Bound(value: values, changed: changed)
    }

    mutating func popOptionalProjectionItems(
        _ originals: [ProjectionItem]?
    ) throws(QueryParameterBindingError) -> Bound<[ProjectionItem]?> {
        guard let originals else {
            return Bound(value: nil, changed: false)
        }
        let values = try popProjectionItems(originals)
        return Bound(value: values.value, changed: values.changed)
    }

    mutating func popAssignments(
        _ originals: [Assignment]
    ) throws(QueryParameterBindingError) -> Bound<[Assignment]> {
        var values = originals
        var changed = false
        for index in values.indices.reversed() {
            let expression = try popExpression()
            if expression.changed {
                values[index] = Assignment(
                    column: originals[index].column,
                    value: expression.value
                )
                changed = true
            }
        }
        return Bound(value: values, changed: changed)
    }

    mutating func popPropertyBindings(
        _ originals: [PropertyBinding]
    ) throws(QueryParameterBindingError) -> Bound<[PropertyBinding]> {
        var values = originals
        var changed = false
        for index in values.indices.reversed() {
            let expression = try popExpression()
            if expression.changed {
                values[index] = PropertyBinding(
                    key: originals[index].key,
                    value: expression.value
                )
                changed = true
            }
        }
        return Bound(value: values, changed: changed)
    }

    mutating func popOptionalPropertyBindings(
        _ originals: [PropertyBinding]?
    ) throws(QueryParameterBindingError) -> Bound<[PropertyBinding]?> {
        guard let originals else {
            return Bound(value: nil, changed: false)
        }
        let values = try popPropertyBindings(originals)
        return Bound(value: values.value, changed: values.changed)
    }

    mutating func popSortKeys(
        _ originals: [SortKey]
    ) throws(QueryParameterBindingError) -> Bound<[SortKey]> {
        var values = originals
        var changed = false
        for index in values.indices.reversed() {
            let expression = try popExpression()
            if expression.changed {
                values[index] = SortKey(
                    expression.value,
                    direction: originals[index].direction,
                    nulls: originals[index].nulls
                )
                changed = true
            }
        }
        return Bound(value: values, changed: changed)
    }

    mutating func popOptionalSortKeys(
        _ originals: [SortKey]?
    ) throws(QueryParameterBindingError) -> Bound<[SortKey]?> {
        guard let originals else {
            return Bound(value: nil, changed: false)
        }
        let values = try popSortKeys(originals)
        return Bound(value: values.value, changed: values.changed)
    }

    mutating func popOptionalNamedSubqueries(
        _ originals: [NamedSubquery]?
    ) throws(QueryParameterBindingError) -> Bound<[NamedSubquery]?> {
        guard let originals else {
            return Bound(value: nil, changed: false)
        }
        var values = originals
        var changed = false
        for index in values.indices.reversed() {
            let query = try popSelect()
            if query.changed {
                values[index] = NamedSubquery(
                    name: originals[index].name,
                    columns: originals[index].columns,
                    query: query.value,
                    materialized: originals[index].materialized
                )
                changed = true
            }
        }
        return Bound(value: values, changed: changed)
    }

    mutating func popJoinCondition(
        _ condition: JoinCondition?
    ) throws(QueryParameterBindingError) -> Bound<JoinCondition?> {
        guard case .on = condition else {
            return Bound(value: condition, changed: false)
        }
        let expression = try popExpression()
        return Bound(
            value: expression.changed ? .on(expression.value) : condition,
            changed: expression.changed
        )
    }

    mutating func popOptionalGraphTableColumns(
        _ originals: [GraphTableColumn]?
    ) throws(QueryParameterBindingError) -> Bound<[GraphTableColumn]?> {
        guard let originals else {
            return Bound(value: nil, changed: false)
        }
        var values = originals
        var changed = false
        for index in values.indices.reversed() {
            let expression = try popExpression()
            if expression.changed {
                values[index] = GraphTableColumn(
                    expression: expression.value,
                    alias: originals[index].alias
                )
                changed = true
            }
        }
        return Bound(value: values, changed: changed)
    }

    mutating func popSources(
        _ originals: [DataSource]
    ) throws(QueryParameterBindingError) -> Bound<[DataSource]> {
        var values = originals
        var changed = false
        for index in values.indices.reversed() {
            let source = try popSource()
            if source.changed {
                values[index] = source.value
                changed = true
            }
        }
        return Bound(value: values, changed: changed)
    }

    mutating func popPathPatterns(
        _ originals: [PathPattern]
    ) throws(QueryParameterBindingError) -> Bound<[PathPattern]> {
        var values = originals
        var changed = false
        for index in values.indices.reversed() {
            let pattern = try popPathPattern()
            if pattern.changed {
                values[index] = pattern.value
                changed = true
            }
        }
        return Bound(value: values, changed: changed)
    }

    mutating func popPathElements(
        _ originals: [PathElement]
    ) throws(QueryParameterBindingError) -> Bound<[PathElement]> {
        var values = originals
        var changed = false
        for index in values.indices.reversed() {
            let element = try popPathElement()
            if element.changed {
                values[index] = element.value
                changed = true
            }
        }
        return Bound(value: values, changed: changed)
    }

    mutating func popAggregateBindings(
        _ originals: [AggregateBinding]
    ) throws(QueryParameterBindingError) -> Bound<[AggregateBinding]> {
        var values = originals
        var changed = false
        for index in values.indices.reversed() {
            let aggregate = try popAggregate()
            if aggregate.changed {
                values[index] = AggregateBinding(
                    variable: originals[index].variable,
                    aggregate: aggregate.value
                )
                changed = true
            }
        }
        return Bound(value: values, changed: changed)
    }

    mutating func popCaseWhenPairs(
        _ originals: [CaseWhenPair]
    ) throws(QueryParameterBindingError) -> Bound<[CaseWhenPair]> {
        var values = originals
        var changed = false
        for index in values.indices.reversed() {
            let result = try popExpression()
            let condition = try popExpression()
            if condition.changed || result.changed {
                values[index] = CaseWhenPair(
                    condition: condition.value,
                    result: result.value
                )
                changed = true
            }
        }
        return Bound(value: values, changed: changed)
    }

    mutating func popInsertSource(
        _ source: InsertSource
    ) throws(QueryParameterBindingError) -> Bound<InsertSource> {
        switch source {
        case .values(let rows):
            let values = try popExpressionRows(rows)
            return Bound(
                value: values.changed ? .values(values.value) : source,
                changed: values.changed
            )
        case .select:
            let query = try popSelect()
            return Bound(
                value: query.changed ? .select(query.value) : source,
                changed: query.changed
            )
        case .defaultValues:
            return Bound(value: source, changed: false)
        }
    }

    mutating func popConflictAction(
        _ action: OnConflictAction?
    ) throws(QueryParameterBindingError) -> Bound<OnConflictAction?> {
        guard case .doUpdate(let assignments, let predicate) = action else {
            return Bound(value: action, changed: false)
        }
        let boundPredicate = try popOptionalExpression(predicate)
        let boundAssignments = try popAssignments(assignments)
        let changed = boundPredicate.changed || boundAssignments.changed
        return Bound(
            value: changed
                ? .doUpdate(
                    assignments: boundAssignments.value,
                    where: boundPredicate.value
                )
                : action,
            changed: changed
        )
    }

    mutating func popBinaryExpression(
        original: Expression,
        build: (Expression, Expression) -> Expression
    ) throws(QueryParameterBindingError) -> Bound<Expression> {
        let right = try popExpression()
        let left = try popExpression()
        let changed = left.changed || right.changed
        return Bound(
            value: changed ? build(left.value, right.value) : original,
            changed: changed
        )
    }

    mutating func popUnaryExpression(
        original: Expression,
        build: (Expression) -> Expression
    ) throws(QueryParameterBindingError) -> Bound<Expression> {
        let value = try popExpression()
        return Bound(
            value: value.changed ? build(value.value) : original,
            changed: value.changed
        )
    }

    mutating func popUnaryAggregate(
        original: AggregateFunction,
        build: (Expression) -> AggregateFunction
    ) throws(QueryParameterBindingError) -> Bound<AggregateFunction> {
        let value = try popExpression()
        return Bound(
            value: value.changed ? build(value.value) : original,
            changed: value.changed
        )
    }

    mutating func popBinaryGraphPattern(
        original: GraphPattern,
        build: (GraphPattern, GraphPattern) -> GraphPattern
    ) throws(QueryParameterBindingError) -> Bound<GraphPattern> {
        let right = try popGraphPattern()
        let left = try popGraphPattern()
        let changed = left.changed || right.changed
        return Bound(
            value: changed ? build(left.value, right.value) : original,
            changed: changed
        )
    }
}

// MARK: - Literal Conversion

private extension QueryParameterBindingTraversal {
    func literal(
        for reference: QueryParameterReference
    ) throws(QueryParameterBindingError) -> Literal {
        let value: FieldValue
        switch reference {
        case .position(let position):
            guard position > 0 else {
                throw .invalidPosition(position)
            }
            guard let resolved = positions[position] else {
                throw .missingPosition(position)
            }
            value = resolved
        case .name(let name):
            guard let resolved = names[name] else {
                throw .missingName(name)
            }
            value = resolved
        }

        do {
            return try value.queryLiteral
        } catch {
            throw .unsupportedValue(reference)
        }
    }
}
