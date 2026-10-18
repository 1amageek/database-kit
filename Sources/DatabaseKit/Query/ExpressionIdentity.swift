import DatabaseTypes

/// Exact declaration identity over direct Expression edges, without recursive witnesses.
enum ExpressionIdentity {
    static func areEqual(_ lhs: Expression, _ rhs: Expression) -> Bool {
        var left = Cursor(lhs)
        var right = Cursor(rhs)
        while let token = left.next() {
            guard let other = right.next(), token == other else { return false }
        }
        return right.next() == nil
    }

    static func hash(_ expression: Expression, into hasher: inout Hasher) {
        var cursor = Cursor(expression)
        while let token = cursor.next() { hasher.combine(token) }
    }

    static func areEqual(_ lhs: SelectQuery, _ rhs: SelectQuery) -> Bool {
        equal(Cursor(.select(lhs)), Cursor(.select(rhs)))
    }

    static func areEqual(_ lhs: DataSource, _ rhs: DataSource) -> Bool {
        equal(Cursor(.source(lhs)), Cursor(.source(rhs)))
    }

    static func hash(_ query: SelectQuery, into hasher: inout Hasher) { hash(Cursor(.select(query)), into: &hasher) }
    static func hash(_ source: DataSource, into hasher: inout Hasher) { hash(Cursor(.source(source)), into: &hasher) }

    static func areEqual(_ lhs: GroupingElement, _ rhs: GroupingElement) -> Bool {
        equal(Cursor(.grouping(lhs)), Cursor(.grouping(rhs)))
    }

    static func hash(_ value: GroupingElement, into hasher: inout Hasher) {
        hash(Cursor(.grouping(value)), into: &hasher)
    }

    private static func equal(_ lhs: Cursor, _ rhs: Cursor) -> Bool {
        var left = lhs
        var right = rhs
        while let token = left.next() {
            guard let other = right.next(), token == other else { return false }
        }
        return right.next() == nil
    }

    private static func hash(_ input: Cursor, into hasher: inout Hasher) {
        var cursor = input
        while let token = cursor.next() { hasher.combine(token) }
    }

    static func nameEqual(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (.some(let lhs), .some(let rhs)): return ExactName(value: lhs) == ExactName(value: rhs)
        default: return false
        }
    }

    static func namesEqual(_ lhs: [String]?, _ rhs: [String]?) -> Bool {
        ExactNames(values: lhs) == ExactNames(values: rhs)
    }

    static func hashName(_ value: String?, into hasher: inout Hasher) {
        hasher.combine(value != nil)
        if let value { ExactName(value: value).hash(into: &hasher) }
    }

    static func hashNames(_ values: [String]?, into hasher: inout Hasher) {
        ExactNames(values: values).hash(into: &hasher)
    }

    static func namedStatementMetadataEqual(_ lhs: SQLNamedStatement, _ rhs: SQLNamedStatement) -> Bool {
        guard nameEqual(lhs.name, rhs.name), namesEqual(lhs.columns, rhs.columns), lhs.materialized == rhs.materialized else { return false }
        switch (lhs.search, rhs.search) {
        case (nil, nil): break
        case (.some(let a), .some(let b)):
            guard a.order == b.order, namesEqual(a.columns, b.columns), nameEqual(a.sequenceColumn, b.sequenceColumn) else { return false }
        default: return false
        }
        switch (lhs.cycle, rhs.cycle) {
        case (nil, nil): break
        case (.some(let a), .some(let b)):
            guard namesEqual(a.columns, b.columns), nameEqual(a.markColumn, b.markColumn), nameEqual(a.pathColumn, b.pathColumn),
                  a.markValue == b.markValue, a.defaultValue == b.defaultValue else { return false }
        default: return false
        }
        return true
    }

    static func hashNamedStatementMetadata(_ value: SQLNamedStatement, into hasher: inout Hasher) {
        hashName(value.name, into: &hasher); hashNames(value.columns, into: &hasher)
        hasher.combine(value.materialized)
        hasher.combine(value.search != nil)
        if let search = value.search {
            hasher.combine(search.order); hashNames(search.columns, into: &hasher); hashName(search.sequenceColumn, into: &hasher)
        }
        hasher.combine(value.cycle != nil)
        if let cycle = value.cycle {
            hashNames(cycle.columns, into: &hasher); hashName(cycle.markColumn, into: &hasher); hashName(cycle.pathColumn, into: &hasher)
            hasher.combine(cycle.markValue); hasher.combine(cycle.defaultValue)
        }
    }

    private struct ExactName: Equatable, Hashable {
        let value: String
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.value.utf8.elementsEqual(rhs.value.utf8) }
        func hash(into hasher: inout Hasher) {
            hasher.combine(value.utf8.count)
            for byte in value.utf8 { hasher.combine(byte) }
        }
    }

    private struct ExactNames: Equatable, Hashable {
        let values: [String]?
        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs.values, rhs.values) {
            case (nil, nil): return true
            case (.some(let l), .some(let r)):
                guard l.count == r.count else { return false }
                for index in l.indices where !l[index].utf8.elementsEqual(r[index].utf8) { return false }
                return true
            default: return false
            }
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(values != nil)
            guard let values else { return }
            hasher.combine(values.count)
            for value in values { ExactName(value: value).hash(into: &hasher) }
        }
    }

    private enum Token: Equatable, Hashable {
        case kind(Int)
        case count(Int)
        case bool(Bool)
        case string(ExactName)
        case optionalString(ExactName?)
        case literal(Literal)
        case parameter(QueryParameterReference)
        case dataType(DataType)
        case fieldObject(FieldObject)
        case strings(ExactNames)
        case uint64(UInt64)
        case joinType(JoinType)
        case materialization(Materialization?)
        case dataset(SPARQLDataset)
        case collation(SQLCollation)
        case setOperator(SetOperator)
        case setQuantifier(SetQuantifier)
        case basicElements([BasicGraphPatternElement])
        case literalRows([[Literal?]])
        case pathMode(PathMode?)
        case pathQuantifier(PathQuantifier)
        case edgeDirection(EdgeDirection)
        case term(SPARQLTerm)
        case index(IndexScanSource)
        case fusionStrategy(FusionStrategy)
        case fusionScoring(FusionScoring?)
        case fusionRequirement(FusionInputRequirement)
        case fusionIndex(FusionIndexSource)
        case fusionConnected(FusionConnectedSource)
        case direction(SortDirection)
        case nulls(NullOrdering?)
        case current(SQLCurrentValueKind)
        case optionalInt(Int?)
        case pattern(PatternMatchKind)
        case truth(TruthValue)
        case comparison(ComparisonOperator)
        case quantifier(ComparisonQuantifier)
    }

    private static func nameToken(_ value: String) -> Token { .string(ExactName(value: value)) }
    private static func optionalName(_ value: String?) -> Token { .optionalString(value.map { ExactName(value: $0) }) }
    private static func names(_ value: [String]?) -> Token { .strings(ExactNames(values: value)) }

    private enum Step {
        case select(SelectQuery), source(DataSource), pattern(GraphPattern)
        case projection([ProjectionItem], Int), rows([[Expression]], Int), ctes([NamedSubquery], Int)
        case optionalExpressions([Expression]?), optionalSorts([SortKey]?)
        case count(QueryCount?), limit(QueryLimit?), quantifier(SelectQuantifier), access(AccessPath?)
        case match(MatchPattern), paths([PathPattern], Int), path(PathPattern), elements([PathElement], Int)
        case properties([PropertyBinding]?, Int), graphColumns([GraphTableColumn]?, Int)
        case aggregateBindings([AggregateBinding], Int)
        case fusionStages([FusionStageSource], Int), fusionInputs([FusionInput], Int)
        case expression(Expression)
        case optionalExpression(Expression?)
        case expressions([Expression], index: Int)
        case subscripts([ArraySubscript], index: Int)
        case pairs([CaseWhenPair], index: Int)
        case sortKeys([SortKey], index: Int)
        case aggregate(AggregateFunction)
        case sqlAggregate(SQLAggregateCall)
        case grouping(GroupingElement), groupings([GroupingElement], Int)
        case groupingSets([[GroupingElement]], Int)
        case windows([NamedWindow], Int), window(WindowCall), specification(WindowSpecification)
        case frame(WindowFrame), bound(WindowFrameBound)
        case token(Token)
    }

    private struct Cursor {
        // Arrays retain COW input owners; one cursor frame per active collection
        // avoids an intermediate flattened tree or workspace proportional to width.
        private var steps: [Step]

        init(_ step: Step) { steps = [step] }

        init(_ expression: Expression) {
            steps = [.expression(expression)]
        }

        mutating func next() -> Token? {
            while let step = steps.popLast() {
                switch step {
                case .select(let query):
                    steps.append(.token(.dataset(query.dataset)))
                    steps.append(.token(.bool(query.reduced)))
                    steps.append(.token(.bool(query.withRecursive)))
                    steps.append(.limit(query.pagination.limit))
                    steps.append(.count(query.pagination.offset))
                    steps.append(.optionalSorts(query.orderBy))
                    steps.append(.quantifier(query.quantifier))
                    steps.append(.windows(query.windows, 0)); steps.append(.token(.count(query.windows.count)))
                    steps.append(.optionalExpression(query.having))
                    if let groups = query.groupBy { steps.append(.groupings(groups, 0)); steps.append(.token(.count(groups.count))) }
                    steps.append(.token(.bool(query.groupBy != nil)))
                    steps.append(.optionalExpression(query.filter))
                    steps.append(.access(query.accessPath))
                    steps.append(.source(query.source))
                    steps.append(.projection(query.projection, 0))
                    if let ctes = query.subqueries { steps.append(.ctes(ctes, 0)); steps.append(.token(.count(ctes.count))) }
                    steps.append(.token(.bool(query.subqueries != nil)))
                    return .kind(200)
                case .source(let source): return enqueue(source)
                case .pattern(let pattern): return enqueue(pattern)
                case .projection(let values, let index):
                    if index == 0 { steps.append(.token(.count(values.count))) }
                    guard index < values.count else { continue }
                    steps.append(.projection(values, index + 1))
                    switch values[index] {
                    case .expression(let expression, let alias):
                        steps.append(.token(optionalName(alias))); steps.append(.expression(expression)); return .kind(0)
                    case .wildcard(let qualifier): steps.append(.token(optionalName(qualifier))); return .kind(1)
                    }
                case .rows(let rows, let index):
                    guard index < rows.count else { continue }
                    steps.append(.rows(rows, index + 1)); list(rows[index])
                case .ctes(let ctes, let index):
                    guard index < ctes.count else { continue }
                    let cte = ctes[index]
                    steps.append(.ctes(ctes, index + 1)); steps.append(.select(cte.query))
                    if let cycle = cte.cycle {
                        if let value = cycle.defaultValue { steps.append(.token(.literal(value))) }
                        steps.append(.token(.bool(cycle.defaultValue != nil)))
                        if let value = cycle.markValue { steps.append(.token(.literal(value))) }
                        steps.append(.token(.bool(cycle.markValue != nil)))
                        steps.append(.token(nameToken(cycle.pathColumn)))
                        steps.append(.token(nameToken(cycle.markColumn)))
                        steps.append(.token(names(cycle.columns)))
                    }
                    steps.append(.token(.bool(cte.cycle != nil)))
                    if let search = cte.search {
                        steps.append(.token(nameToken(search.sequenceColumn)))
                        steps.append(.token(names(search.columns)))
                        steps.append(.token(.bool(search.order == .depthFirst)))
                    }
                    steps.append(.token(.bool(cte.search != nil)))
                    steps.append(.token(.materialization(cte.materialized))); steps.append(.token(names(cte.columns)))
                    return nameToken(cte.name)
                case .optionalExpressions(let values):
                    if let values { list(values) }; return .bool(values != nil)
                case .optionalSorts(let values):
                    if let values { steps.append(.sortKeys(values, index: 0)); steps.append(.token(.count(values.count))) }
                    return .bool(values != nil)
                case .quantifier(let quantifier):
                    switch quantifier {
                    case .all: return .kind(0)
                    case .distinct: return .kind(1)
                    case .distinctOn(let keys): list(keys); return .kind(2)
                    }
                case .count(let count):
                    guard let count else { return .kind(0) }
                    switch count {
                    case .fixed(let value): steps.append(.token(.uint64(value))); return .kind(1)
                    case .expression(let value): steps.append(.expression(value)); return .kind(2)
                    }
                case .limit(let limit):
                    guard let limit else { return .kind(0) }
                    switch limit {
                    case .all: return .kind(1)
                    case .count(let count, let ties): steps.append(.count(count)); steps.append(.token(.bool(ties))); return .kind(2)
                    }
                case .access(let access):
                    guard let access else { return .kind(0) }
                    switch access {
                    case .index(let index): steps.append(.token(.index(index))); return .kind(1)
                    case .fusion(let fusion):
                        steps.append(.fusionStages(fusion.stages, 0)); steps.append(.token(.count(fusion.stages.count)))
                        steps.append(.token(.fusionStrategy(fusion.strategy))); return .kind(2)
                    }
                case .match(let match):
                    steps.append(.optionalExpression(match.where)); steps.append(.paths(match.paths, 0)); return .count(match.paths.count)
                case .paths(let paths, let index):
                    guard index < paths.count else { continue }
                    steps.append(.paths(paths, index + 1)); steps.append(.path(paths[index]))
                case .path(let path):
                    steps.append(.elements(path.elements, 0)); steps.append(.token(.count(path.elements.count)))
                    steps.append(.token(.pathMode(path.mode))); return optionalName(path.pathVariable)
                case .elements(let elements, let index):
                    guard index < elements.count else { continue }
                    steps.append(.elements(elements, index + 1))
                    switch elements[index] {
                    case .node(let node):
                        steps.append(.properties(node.properties, 0)); steps.append(.token(names(node.labels)))
                        steps.append(.token(optionalName(node.variable))); return .kind(0)
                    case .edge(let edge):
                        steps.append(.properties(edge.properties, 0)); steps.append(.token(.edgeDirection(edge.direction)))
                        steps.append(.token(names(edge.labels))); steps.append(.token(optionalName(edge.variable))); return .kind(1)
                    case .quantified(let path, let quantifier):
                        steps.append(.path(path)); steps.append(.token(.pathQuantifier(quantifier))); return .kind(2)
                    case .alternation(let paths): steps.append(.paths(paths, 0)); steps.append(.token(.count(paths.count))); return .kind(3)
                    }
                case .properties(let properties, let index):
                    if index == 0 {
                        steps.append(.token(.count(properties?.count ?? 0)))
                        steps.append(.token(.bool(properties != nil)))
                    }
                    guard let properties, index < properties.count else { continue }
                    steps.append(.properties(properties, index + 1)); steps.append(.expression(properties[index].value))
                    return nameToken(properties[index].key)
                case .graphColumns(let columns, let index):
                    if index == 0 {
                        steps.append(.token(.count(columns?.count ?? 0))); steps.append(.token(.bool(columns != nil)))
                    }
                    guard let columns, index < columns.count else { continue }
                    steps.append(.graphColumns(columns, index + 1)); steps.append(.expression(columns[index].expression))
                    return nameToken(columns[index].alias)
                case .aggregateBindings(let values, let index):
                    guard index < values.count else { continue }
                    steps.append(.aggregateBindings(values, index + 1)); steps.append(.aggregate(values[index].aggregate))
                    return nameToken(values[index].variable)
                case .fusionStages(let values, let index):
                    guard index < values.count else { continue }
                    steps.append(.fusionStages(values, index + 1)); steps.append(.fusionInputs(values[index].inputs, 0))
                    return .count(values[index].inputs.count)
                case .fusionInputs(let values, let index):
                    guard index < values.count else { continue }
                    let input = values[index]
                    steps.append(.fusionInputs(values, index + 1)); steps.append(.count(input.limit.map(QueryCount.fixed)))
                    steps.append(.token(.fusionRequirement(input.requirement))); steps.append(.token(.fusionScoring(input.scoring)))
                    switch input.operation {
                    case .index(let source): steps.append(.token(.fusionIndex(source))); return .kind(0)
                    case .connected(let source): steps.append(.token(.fusionConnected(source))); return .kind(1)
                    case .filter(let expression): steps.append(.expression(expression)); return .kind(2)
                    case .order(let keys): steps.append(.sortKeys(keys, index: 0)); steps.append(.token(.count(keys.count))); return .kind(3)
                    }
                case .token(let token): return token
                case .optionalExpression(let value):
                    if let value { steps.append(.expression(value)) }
                    return .bool(value != nil)
                case .expressions(let values, let index):
                    guard index < values.count else { continue }
                    steps.append(.expressions(values, index: index + 1))
                    steps.append(.expression(values[index]))
                case .subscripts(let values, let index):
                    guard index < values.count else { continue }
                    steps.append(.subscripts(values, index: index + 1))
                    switch values[index] {
                    case .index(let value):
                        steps.append(.expression(value))
                        return .kind(0)
                    case .slice(let lower, let upper):
                        steps.append(.optionalExpression(upper))
                        steps.append(.optionalExpression(lower))
                        return .kind(1)
                    }
                case .pairs(let values, let index):
                    guard index < values.count else { continue }
                    steps.append(.pairs(values, index: index + 1))
                    steps.append(.expression(values[index].result))
                    steps.append(.expression(values[index].condition))
                case .sortKeys(let values, let index):
                    guard index < values.count else { continue }
                    let key = values[index]
                    steps.append(.sortKeys(values, index: index + 1))
                    steps.append(.token(.nulls(key.nulls)))
                    steps.append(.token(.direction(key.direction)))
                    steps.append(.expression(key.expression))
                case .grouping(let value):
                    switch value {
                    case .expression(let expression): steps.append(.expression(expression)); return .kind(0)
                    case .rollup(let rows): steps.append(.rows(rows, 0)); steps.append(.token(.count(rows.count))); return .kind(1)
                    case .cube(let rows): steps.append(.rows(rows, 0)); steps.append(.token(.count(rows.count))); return .kind(2)
                    case .groupingSets(let sets): steps.append(.groupingSets(sets, 0)); steps.append(.token(.count(sets.count))); return .kind(3)
                    }
                case .groupings(let values, let index):
                    guard index < values.count else { continue }
                    steps.append(.groupings(values, index + 1)); steps.append(.grouping(values[index]))
                case .groupingSets(let sets, let index):
                    guard index < sets.count else { continue }
                    steps.append(.groupingSets(sets, index + 1)); steps.append(.groupings(sets[index], 0)); return .count(sets[index].count)
                case .sqlAggregate(let call):
                    steps.append(.optionalSorts(call.withinGroup)); steps.append(.optionalExpression(call.filter))
                    steps.append(.sortKeys(call.orderBy, index: 0)); steps.append(.token(.count(call.orderBy.count)))
                    steps.append(.token(.bool(call.distinct))); list(call.arguments)
                    steps.append(.token(optionalName(call.schema))); return nameToken(call.function.rawValue)
                case .windows(let windows, let index):
                    guard index < windows.count else { continue }
                    steps.append(.windows(windows, index + 1)); steps.append(.specification(windows[index].specification))
                    return nameToken(windows[index].name)
                case .window(let call):
                    switch call.reference {
                    case .named(let name): steps.append(.token(nameToken(name))); steps.append(.token(.kind(0)))
                    case .specification(let spec): steps.append(.specification(spec)); steps.append(.token(.kind(1)))
                    }
                    switch call.function {
                    case .aggregate(let aggregate): steps.append(.sqlAggregate(aggregate)); return .kind(0)
                    case .analytic(let function, let arguments): list(arguments); steps.append(.token(nameToken(function.rawValue))); return .kind(1)
                    }
                case .specification(let spec):
                    if let frame = spec.frame { steps.append(.frame(frame)) }
                    steps.append(.token(.bool(spec.frame != nil)))
                    steps.append(.sortKeys(spec.orderBy, index: 0)); steps.append(.token(.count(spec.orderBy.count)))
                    list(spec.partitionBy); return optionalName(spec.inheritedName)
                case .frame(let frame):
                    steps.append(.token(nameToken(frame.exclusion.rawValue))); steps.append(.bound(frame.end)); steps.append(.bound(frame.start))
                    return nameToken(frame.mode.rawValue)
                case .bound(let bound):
                    switch bound {
                    case .unboundedPreceding: return .kind(0)
                    case .preceding(let expression): return unary(expression, kind: 1)
                    case .currentRow: return .kind(2)
                    case .following(let expression): return unary(expression, kind: 3)
                    case .unboundedFollowing: return .kind(4)
                    }
                case .aggregate(let value): return enqueue(value)
                case .expression(let value): return enqueue(value)
                }
            }
            return nil
        }

        private mutating func list(_ values: [Expression]) {
            steps.append(.expressions(values, index: 0))
            steps.append(.token(.count(values.count)))
        }

        private mutating func unary(_ value: Expression, kind: Int) -> Token {
            steps.append(.expression(value))
            return .kind(kind)
        }

        private mutating func binary(_ left: Expression, _ right: Expression, kind: Int) -> Token {
            steps.append(.expression(right))
            steps.append(.expression(left))
            return .kind(kind)
        }

        private mutating func enqueue(_ expression: Expression) -> Token {
            switch expression {
            case .defaultValue: return .kind(63)
            case .grouping(let arguments): list(arguments); return .kind(61)
            case .window(let call): steps.append(.window(call)); return .kind(62)
            case .collate(let expression, let collation):
                steps.append(.token(.collation(collation))); return unary(expression, kind: 56)
            case .arraySubquery(let query): steps.append(.select(query)); return .kind(57)
            case .wholeRow(let name): steps.append(.token(nameToken(name))); return .kind(58)
            case .field(let expression, let name):
                steps.append(.token(nameToken(name))); return unary(expression, kind: 59)
            case .fieldExpansion(let expression): return unary(expression, kind: 60)
            case .arrayAccess(let base, let subscripts):
                steps.append(.subscripts(subscripts, index: 0))
                steps.append(.expression(base))
                steps.append(.token(.count(subscripts.count)))
                return .kind(53)
            case .collectionOperation(let operation, let left, let right):
                let kind = binary(left, right, kind: 54)
                steps.append(.token(.kind(Int(operation.rawValue))))
                return kind
            case .currentValue(let kind, let precision):
                steps.append(.token(.optionalInt(precision)))
                steps.append(.token(.current(kind)))
                return .kind(52)
            case .literal(let value):
                steps.append(.token(.literal(value))); return .kind(0)
            case .array(let values): list(values); return .kind(41)
            case .row(let values): list(values); return .kind(42)
            case .column(let value):
                steps.append(.token(nameToken(value.column))); steps.append(.token(optionalName(value.table))); return .kind(1)
            case .variable(let value):
                steps.append(.token(nameToken(value.name))); return .kind(2)
            case .parameter(let value):
                steps.append(.token(.parameter(value))); return .kind(40)
            case .add(let l, let r): return binary(l, r, kind: 3)
            case .subtract(let l, let r): return binary(l, r, kind: 4)
            case .multiply(let l, let r): return binary(l, r, kind: 5)
            case .divide(let l, let r): return binary(l, r, kind: 6)
            case .modulo(let l, let r): return binary(l, r, kind: 7)
            case .negate(let value): return unary(value, kind: 8)
            case .equal(let l, let r): return binary(l, r, kind: 9)
            case .notEqual(let l, let r): return binary(l, r, kind: 10)
            case .lessThan(let l, let r): return binary(l, r, kind: 11)
            case .lessThanOrEqual(let l, let r): return binary(l, r, kind: 12)
            case .greaterThan(let l, let r): return binary(l, r, kind: 13)
            case .greaterThanOrEqual(let l, let r): return binary(l, r, kind: 14)
            case .and(let l, let r): return binary(l, r, kind: 15)
            case .or(let l, let r): return binary(l, r, kind: 16)
            case .not(let value): return unary(value, kind: 17)
            case .isNull(let value): return unary(value, kind: 18)
            case .isNotNull(let value): return unary(value, kind: 19)
            case .bound(let value):
                steps.append(.token(nameToken(value.name))); return .kind(20)
            case .patternMatch(let subject, let pattern, let escape, let kind):
                steps.append(.optionalExpression(escape))
                steps.append(.expression(pattern))
                steps.append(.expression(subject))
                steps.append(.token(.pattern(kind)))
                return .kind(50)
            case .concatenate(let lhs, let rhs): return binary(lhs, rhs, kind: 51)
            case .regex(let value, let pattern, let flags):
                steps.append(.token(optionalName(flags)))
                steps.append(.token(nameToken(pattern)))
                return unary(value, kind: 22)
            case .between(let value, let low, let high):
                steps.append(.expression(high))
                return binary(value, low, kind: 23)
            case .inList(let value, let values):
                list(values); return unary(value, kind: 24)
            case .notInList(let value, let values):
                list(values); return unary(value, kind: 39)
            case .inSubquery(let value, let query):
                steps.append(.select(query)); return unary(value, kind: 25)
            case .aggregate(let value):
                steps.append(.aggregate(value)); return .kind(26)
            case .function(let value):
                list(value.arguments)
                steps.append(.token(.bool(value.finalArrayIsVariadic)))
                steps.append(.token(.bool(value.distinct)))
                steps.append(.token(nameToken(value.name)))
                steps.append(.token(optionalName(value.schema)))
                return .kind(27)
            case .caseWhen(let operand, let pairs, let fallback):
                steps.append(.optionalExpression(fallback))
                steps.append(.pairs(pairs, index: 0))
                steps.append(.token(.count(pairs.count)))
                steps.append(.optionalExpression(operand))
                return .kind(28)
            case .coalesce(let values): list(values); return .kind(29)
            case .nullIf(let l, let r): return binary(l, r, kind: 30)
            case .cast(let value, let type):
                steps.append(.token(.dataType(type))); return unary(value, kind: 31)
            case .triple(let subject, let predicate, let object):
                steps.append(.expression(object)); return binary(subject, predicate, kind: 32)
            case .isTriple(let value): return unary(value, kind: 33)
            case .subject(let value): return unary(value, kind: 34)
            case .predicate(let value): return unary(value, kind: 35)
            case .object(let value): return unary(value, kind: 36)
            case .subquery(let value):
                steps.append(.select(value)); return .kind(37)
            case .exists(let value):
                steps.append(.select(value)); return .kind(38)
            case .greatest(let values): list(values); return .kind(45)
            case .least(let values): list(values); return .kind(46)
            case .truthTest(let value, let truth, let negated):
                steps.append(.token(.bool(negated)))
                steps.append(.token(.truth(truth)))
                return unary(value, kind: 47)
            case .isDistinctFrom(let left, let right, let negated):
                steps.append(.token(.bool(negated))); return binary(left, right, kind: 48)
            case .quantifiedComparison(let value, let comparison, let quantifier, let source):
                switch source {
                case .array(let value):
                    steps.append(.expression(value)); steps.append(.token(.kind(0)))
                case .subquery(let value):
                    steps.append(.select(value)); steps.append(.token(.kind(1)))
                }
                steps.append(.token(.quantifier(quantifier)))
                steps.append(.token(.comparison(comparison)))
                return unary(value, kind: 49)
            }
        }

        private mutating func enqueue(_ source: DataSource) -> Token {
            switch source {
            case .table(let table):
                steps.append(.token(.fieldObject(table.partitions)))
                steps.append(.token(optionalName(table.alias))); steps.append(.token(optionalName(table.schema)))
                steps.append(.token(nameToken(table.table))); return .kind(100)
            case .tableFunction(let value):
                list(value.function.arguments)
                steps.append(.token(.bool(value.function.finalArrayIsVariadic)))
                steps.append(.token(.bool(value.function.distinct)))
                steps.append(.token(nameToken(value.function.name)))
                steps.append(.token(optionalName(value.function.schema)))
                steps.append(.token(.bool(value.withOrdinality)))
                return .kind(116)
            case .logical(let logical):
                steps.append(.token(nameToken(logical.identifier))); steps.append(.token(nameToken(logical.kindIdentifier))); return .kind(101)
            case .subquery(let query): steps.append(.select(query)); return .kind(102)
            case .join(let join):
                if let condition = join.condition {
                    switch condition {
                    case .on(let expression): steps.append(.expression(expression)); steps.append(.token(.kind(1)))
                    case .using(let columns): steps.append(.token(names(columns))); steps.append(.token(.kind(2)))
                    }
                } else { steps.append(.token(.kind(0))) }
                steps.append(.source(join.right)); steps.append(.source(join.left)); steps.append(.token(.joinType(join.type)))
                return .kind(103)
            case .values(let rows): steps.append(.rows(rows, 0)); steps.append(.token(.count(rows.count))); return .kind(104)
            case .aliased(let source, let name, let columns):
                steps.append(.source(source)); steps.append(.token(names(columns))); steps.append(.token(nameToken(name))); return .kind(114)
            case .setOperation(let operation, let quantifier, let left, let right):
                steps.append(.select(right)); steps.append(.select(left)); steps.append(.token(.setQuantifier(quantifier)))
                steps.append(.token(.setOperator(operation))); return .kind(115)
            case .graphTable(let table):
                steps.append(.graphColumns(table.columns, 0)); steps.append(.match(table.matchPattern))
                steps.append(.token(nameToken(table.graphName))); return .kind(105)
            case .graphPattern(let pattern): steps.append(.pattern(pattern)); return .kind(106)
            case .namedGraph(let name, let pattern): steps.append(.pattern(pattern)); steps.append(.token(nameToken(name))); return .kind(107)
            case .service(let endpoint, let pattern, let silent):
                steps.append(.pattern(pattern)); steps.append(.token(.bool(silent))); steps.append(.token(nameToken(endpoint))); return .kind(108)
            #if DATABASE_KIT_MULTI_BASE
            case .base(let id, let source):
                steps.append(.source(source)); steps.append(.token(nameToken(id.value))); return .kind(113)
            #endif
            }
        }

        private mutating func enqueue(_ pattern: GraphPattern) -> Token {
            switch pattern {
            case .basic(let basic):
                steps.append(.token(.basicElements(basic.elements)))
                return .kind(300)
            case .join(let l, let r), .optional(let l, let r), .union(let l, let r), .minus(let l, let r), .lateral(let l, let r):
                steps.append(.pattern(r)); steps.append(.pattern(l))
                switch pattern {
                case .join: return .kind(301)
                case .optional: return .kind(302)
                case .union: return .kind(303)
                case .minus: return .kind(304)
                default: return .kind(305)
                }
            case .filter(let pattern, let expression): steps.append(.expression(expression)); steps.append(.pattern(pattern)); return .kind(306)
            case .graph(let name, let pattern): steps.append(.pattern(pattern)); steps.append(.token(.term(name))); return .kind(307)
            case .service(let endpoint, let pattern, let silent):
                steps.append(.pattern(pattern)); steps.append(.token(.bool(silent))); steps.append(.token(nameToken(endpoint))); return .kind(308)
            case .bind(let pattern, let variable, let expression):
                steps.append(.expression(expression)); steps.append(.pattern(pattern)); steps.append(.token(nameToken(variable))); return .kind(309)
            case .values(let variables, let bindings):
                steps.append(.token(names(variables)))
                steps.append(.token(.literalRows(bindings)))
                steps.append(.token(.count(bindings.count))); return .kind(310)
            case .subquery(let query): steps.append(.select(query)); return .kind(311)
            case .groupBy(let pattern, let expressions, let aggregates):
                steps.append(.aggregateBindings(aggregates, 0)); steps.append(.token(.count(aggregates.count)))
                list(expressions); steps.append(.pattern(pattern)); return .kind(312)
            }
        }

        private mutating func enqueue(_ aggregate: AggregateFunction) -> Token {
            switch aggregate {
            case .sql(let call): steps.append(.sqlAggregate(call)); return .kind(8)
            case .count(let value, let distinct):
                steps.append(.token(.bool(distinct)))
                steps.append(.optionalExpression(value))
                return .kind(0)
            case .sum(let value, let distinct):
                steps.append(.token(.bool(distinct))); return unary(value, kind: 1)
            case .avg(let value, let distinct):
                steps.append(.token(.bool(distinct))); return unary(value, kind: 2)
            case .min(let value): return unary(value, kind: 3)
            case .max(let value): return unary(value, kind: 4)
            case .groupConcat(let value, let separator, let distinct):
                steps.append(.token(.bool(distinct)))
                steps.append(.token(optionalName(separator)))
                return unary(value, kind: 5)
            case .sample(let value): return unary(value, kind: 6)
            case .arrayAgg(let value, let orderBy, let distinct):
                steps.append(.token(.bool(distinct)))
                if let orderBy {
                    steps.append(.sortKeys(orderBy, index: 0))
                    steps.append(.token(.count(orderBy.count)))
                }
                steps.append(.token(.bool(orderBy != nil)))
                return unary(value, kind: 7)
            }
        }
    }
}
