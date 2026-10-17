/// Collects query references without recursing through query/source/expression cycles.
struct QueryReferenceCollector {
    private(set) var variables: Set<String> = []
    private(set) var columns: Set<ColumnRef> = []
    private var steps: [Step] = []

    static func collect(_ query: SelectQuery) -> Self {
        var collector = Self()
        collector.steps.append(.query(query))
        collector.run()
        return collector
    }

    static func collect(_ expression: Expression) -> Self {
        var collector = Self()
        collector.steps.append(.expression(expression))
        collector.run()
        return collector
    }

    private enum Step {
        case grouping(GroupingElement), groupings([GroupingElement], Int), groupingSets([[GroupingElement]], Int)
        case sqlAggregate(SQLAggregateCall), window(WindowCall), specification(WindowSpecification), windows([NamedWindow], Int)
        case query(SelectQuery), source(DataSource), expression(Expression), aggregate(AggregateFunction)
        case expressions([Expression], Int), projection([ProjectionItem], Int), sorts([SortKey], Int)
        case ctes([NamedSubquery], Int), rows([[Expression]], Int), pairs([CaseWhenPair], Int)
        case subscripts([ArraySubscript], Int), pattern(GraphPattern), term(SPARQLTerm)
        case basic([BasicGraphPatternElement], Int), match(MatchPattern), paths([PathPattern], Int)
        case path(PathPattern), elements([PathElement], Int), properties([PropertyBinding], Int)
        case graphColumns([GraphTableColumn], Int), bindings([AggregateBinding], Int)
        case fusionStages([FusionStageSource], Int), fusionInputs([FusionInput], Int)
    }

    private mutating func expression(_ value: Expression?) {
        if let value { steps.append(.expression(value)) }
    }

    private mutating func count(_ value: QueryCount?) {
        if case .expression(let expression) = value { steps.append(.expression(expression)) }
    }

    private mutating func run() {
        while let step = steps.popLast() {
            switch step {
            case .query(let query):
                if case .count(let count, _) = query.pagination.limit { self.count(count) }
                count(query.pagination.offset)
                steps.append(.sorts(query.orderBy ?? [], 0))
                if case .distinctOn(let keys) = query.quantifier { steps.append(.expressions(keys, 0)) }
                expression(query.having)
                steps.append(.groupings(query.groupBy ?? [], 0))
                steps.append(.windows(query.windows, 0))
                expression(query.filter)
                steps.append(.source(query.source))
                steps.append(.projection(query.projection, 0))
                steps.append(.ctes(query.subqueries ?? [], 0))
                if case .fusion(let source) = query.accessPath { steps.append(.fusionStages(source.stages, 0)) }
            case .source(let source):
                switch source {
                case .table, .logical: break
                case .tableFunction(let value): steps.append(.expressions(value.function.arguments, 0))
                case .subquery(let query): steps.append(.query(query))
                case .aliased(let child, _, _): steps.append(.source(child))
                case .setOperation(_, _, let left, let right):
                    steps.append(.query(right)); steps.append(.query(left))
                case .values(let rows): steps.append(.rows(rows, 0))
                case .join(let join):
                    if case .on(let predicate) = join.condition { expression(predicate) }
                    steps.append(.source(join.right)); steps.append(.source(join.left))
                case .graphPattern(let pattern), .namedGraph(_, let pattern), .service(_, let pattern, _):
                    steps.append(.pattern(pattern))
                case .graphTable(let table):
                    steps.append(.graphColumns(table.columns ?? [], 0)); steps.append(.match(table.matchPattern))
                #if DATABASE_KIT_MULTI_BASE
                case .base(_, let child): steps.append(.source(child))
                #endif
                }
            case .expression(let value):
                switch value {
                case .grouping(let expressions): steps.append(.expressions(expressions, 0))
                case .window(let call): steps.append(.window(call))
                case .column(let column): columns.insert(column)
                case .variable(let variable), .bound(let variable): variables.insert(variable.name)
                case .wholeRow, .literal, .currentValue, .parameter: break
                case .add(let l, let r), .subtract(let l, let r), .multiply(let l, let r),
                     .divide(let l, let r), .modulo(let l, let r), .concatenate(let l, let r),
                     .equal(let l, let r), .notEqual(let l, let r), .lessThan(let l, let r),
                     .lessThanOrEqual(let l, let r), .greaterThan(let l, let r),
                     .greaterThanOrEqual(let l, let r), .and(let l, let r), .or(let l, let r),
                     .nullIf(let l, let r), .isDistinctFrom(let l, let r, _), .collectionOperation(_, let l, let r):
                    expression(r); expression(l)
                case .negate(let e), .not(let e), .isNull(let e), .isNotNull(let e), .truthTest(let e, _, _),
                     .regex(let e, _, _), .cast(let e, _), .isTriple(let e), .subject(let e),
                     .predicate(let e), .object(let e), .collate(let e, _), .field(let e, _), .fieldExpansion(let e):
                    expression(e)
                case .array(let values), .row(let values), .coalesce(let values), .greatest(let values), .least(let values):
                    steps.append(.expressions(values, 0))
                case .arrayAccess(let base, let subscripts):
                    steps.append(.subscripts(subscripts, 0)); expression(base)
                case .between(let e, let low, let high), .triple(let e, let low, let high):
                    expression(high); expression(low); expression(e)
                case .patternMatch(let subject, let pattern, let escape, _):
                    expression(escape); expression(pattern); expression(subject)
                case .inList(let e, let values), .notInList(let e, let values):
                    steps.append(.expressions(values, 0)); expression(e)
                case .inSubquery(let e, let query): steps.append(.query(query)); expression(e)
                case .subquery(let query), .exists(let query), .arraySubquery(let query): steps.append(.query(query))
                case .quantifiedComparison(let e, _, _, let source):
                    switch source {
                    case .array(let array): expression(array)
                    case .subquery(let query): steps.append(.query(query))
                    }
                    expression(e)
                case .function(let call): steps.append(.expressions(call.arguments, 0))
                case .aggregate(let aggregate): steps.append(.aggregate(aggregate))
                case .caseWhen(let operand, let pairs, let fallback):
                    expression(fallback); steps.append(.pairs(pairs, 0)); expression(operand)
                }
            case .aggregate(let aggregate):
                switch aggregate {
                case .sql(let call): steps.append(.sqlAggregate(call))
                case .count(let e, _): expression(e)
                case .sum(let e, _), .avg(let e, _), .min(let e), .max(let e), .groupConcat(let e, _, _), .sample(let e): expression(e)
                case .arrayAgg(let e, let order, _): steps.append(.sorts(order ?? [], 0)); expression(e)
                }
            case .grouping(let value):
                switch value {
                case .expression(let value): expression(value)
                case .rollup(let rows), .cube(let rows): steps.append(.rows(rows, 0))
                case .groupingSets(let sets): steps.append(.groupingSets(sets, 0))
                }
            case .groupings(let values, let index):
                guard index < values.count else { continue }
                steps.append(.groupings(values, index + 1)); steps.append(.grouping(values[index]))
            case .groupingSets(let sets, let index):
                guard index < sets.count else { continue }
                steps.append(.groupingSets(sets, index + 1)); steps.append(.groupings(sets[index], 0))
            case .sqlAggregate(let call):
                steps.append(.sorts(call.withinGroup ?? [], 0)); expression(call.filter)
                steps.append(.sorts(call.orderBy, 0)); steps.append(.expressions(call.arguments, 0))
            case .window(let call):
                if case .specification(let spec) = call.reference { steps.append(.specification(spec)) }
                switch call.function {
                case .aggregate(let call): steps.append(.sqlAggregate(call))
                case .analytic(_, let arguments): steps.append(.expressions(arguments, 0))
                }
            case .windows(let values, let index):
                guard index < values.count else { continue }
                steps.append(.windows(values, index + 1)); steps.append(.specification(values[index].specification))
            case .specification(let spec):
                steps.append(.expressions(spec.partitionBy, 0)); steps.append(.sorts(spec.orderBy, 0))
                if let frame = spec.frame {
                    for bound in [frame.start, frame.end] {
                        switch bound { case .preceding(let value), .following(let value): expression(value); default: break }
                    }
                }
            case .expressions(let values, let index):
                guard index < values.count else { continue }
                steps.append(.expressions(values, index + 1)); expression(values[index])
            case .projection(let values, let index):
                guard index < values.count else { continue }
                steps.append(.projection(values, index + 1))
                if case .expression(let expression, _) = values[index] { self.expression(expression) }
            case .sorts(let values, let index):
                guard index < values.count else { continue }
                steps.append(.sorts(values, index + 1)); expression(values[index].expression)
            case .ctes(let values, let index):
                guard index < values.count else { continue }
                steps.append(.ctes(values, index + 1)); steps.append(.query(values[index].query))
            case .rows(let values, let index):
                guard index < values.count else { continue }
                steps.append(.rows(values, index + 1)); steps.append(.expressions(values[index], 0))
            case .pairs(let values, let index):
                guard index < values.count else { continue }
                steps.append(.pairs(values, index + 1)); expression(values[index].result); expression(values[index].condition)
            case .subscripts(let values, let index):
                guard index < values.count else { continue }
                steps.append(.subscripts(values, index + 1))
                switch values[index] {
                case .index(let value): expression(value)
                case .slice(let lower, let upper): expression(upper); expression(lower)
                }
            case .pattern(let pattern):
                switch pattern {
                case .basic(let basic): steps.append(.basic(basic.elements, 0))
                case .join(let l, let r), .optional(let l, let r), .union(let l, let r), .minus(let l, let r), .lateral(let l, let r):
                    steps.append(.pattern(r)); steps.append(.pattern(l))
                case .filter(let child, let e), .bind(let child, _, let e):
                    expression(e); steps.append(.pattern(child))
                    if case .bind(_, let name, _) = pattern { variables.insert(name) }
                case .graph(let name, let child): steps.append(.term(name)); steps.append(.pattern(child))
                case .service(_, let child, _): steps.append(.pattern(child))
                case .values(let names, _): variables.formUnion(names)
                case .subquery(let query): steps.append(.query(query))
                case .groupBy(let child, let keys, let bindings):
                    steps.append(.bindings(bindings, 0)); steps.append(.expressions(keys, 0)); steps.append(.pattern(child))
                }
            case .term(let term):
                switch term {
                case .variable(let name): variables.insert(name)
                case .tripleTerm(let s, let p, let o): steps.append(.term(o)); steps.append(.term(p)); steps.append(.term(s))
                case .reifiedTriple(let s, let p, let o, let r):
                    steps.append(.term(r)); steps.append(.term(o)); steps.append(.term(p)); steps.append(.term(s))
                case .iri, .literal, .blankNode: break
                }
            case .basic(let values, let index):
                guard index < values.count else { continue }
                steps.append(.basic(values, index + 1))
                switch values[index] {
                case .triple(let triple): steps.append(.term(triple.object)); steps.append(.term(triple.predicate)); steps.append(.term(triple.subject))
                case .propertyPath(let path): steps.append(.term(path.object)); steps.append(.term(path.subject))
                }
            case .match(let match): expression(match.where); steps.append(.paths(match.paths, 0))
            case .paths(let values, let index):
                guard index < values.count else { continue }
                steps.append(.paths(values, index + 1)); steps.append(.path(values[index]))
            case .path(let path):
                if let name = path.pathVariable { variables.insert(name) }
                steps.append(.elements(path.elements, 0))
            case .elements(let values, let index):
                guard index < values.count else { continue }
                steps.append(.elements(values, index + 1))
                switch values[index] {
                case .node(let node): if let name = node.variable { variables.insert(name) }; steps.append(.properties(node.properties ?? [], 0))
                case .edge(let edge): if let name = edge.variable { variables.insert(name) }; steps.append(.properties(edge.properties ?? [], 0))
                case .quantified(let path, _): steps.append(.path(path))
                case .alternation(let paths): steps.append(.paths(paths, 0))
                }
            case .properties(let values, let index):
                guard index < values.count else { continue }
                steps.append(.properties(values, index + 1)); expression(values[index].value)
            case .graphColumns(let values, let index):
                guard index < values.count else { continue }
                steps.append(.graphColumns(values, index + 1)); expression(values[index].expression)
            case .bindings(let values, let index):
                guard index < values.count else { continue }
                variables.insert(values[index].variable)
                steps.append(.bindings(values, index + 1)); steps.append(.aggregate(values[index].aggregate))
            case .fusionStages(let values, let index):
                guard index < values.count else { continue }
                steps.append(.fusionStages(values, index + 1)); steps.append(.fusionInputs(values[index].inputs, 0))
            case .fusionInputs(let values, let index):
                guard index < values.count else { continue }
                steps.append(.fusionInputs(values, index + 1))
                switch values[index].operation {
                case .filter(let e): expression(e)
                case .order(let keys): steps.append(.sorts(keys, 0))
                case .index(let source):
                    if case .matching(_, let fields, _) = source.selection { for field in fields { columns.insert(ColumnRef(field.name)) } }
                case .connected(let source): columns.insert(ColumnRef(source.resultField.name))
                }
            }
        }
    }
}
