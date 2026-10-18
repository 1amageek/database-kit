import DatabaseTypes

/// Performs bounded, non-recursive validation of canonical QueryIR.
///
/// The explicit validation-step stack ensures adversarial QueryIR cannot exhaust
/// the process stack before semantic validation reports a typed resource error.
public enum QueryStructuralValidator {
    /// Admits all block steps and parameter payloads against one cumulative ledger.
    public static func validate(
        _ block: SQLBlock,
        parameters: [QueryParameter] = [],
        limits: QueryStructuralLimits = .default
    ) throws(QueryStructuralValidationError) {
        guard !block.steps.isEmpty else { throw .emptySQLBlock }
        var validation = ValidationTraversal(limits: limits)
        try validation.ledger.consume(.totalNodes)
        try validation.ledger.consume(.collectionElements, amount: UInt64(block.steps.count))
        for step in block.steps {
            try validation.ledger.consume(.totalNodes)
            switch step {
            case .statement(let statement):
                try validation.validate([rootValidationStep(for: statement)])
            case .setConstraints(let control):
                if case .named(let names) = control.selection {
                    try validation.ledger.consume(.collectionElements, amount: UInt64(names.count))
                    for name in names {
                        try validation.ledger.consume(.retainedBytes, amount: UInt64(name.utf8.count))
                    }
                }
            case .sequence(let command):
                let sequence: SQLSequence
                switch command {
                case .create(let value): sequence = value
                case .alter(let value, let restart):
                    if let restart, restart < value.minimum || restart > value.maximum {
                        throw .invalidSQLControl
                    }
                    sequence = value
                case .drop(let id, _):
                    guard !id.isEmpty, !id.utf8.contains(0) else { throw .invalidSQLControl }
                    try validation.ledger.consume(.retainedBytes, amount: UInt64(id.utf8.count))
                    continue
                }
                try validation.ledger.consume(.totalNodes)
                for value in [sequence.id, sequence.namespaceID, sequence.name] {
                    try validation.ledger.consume(.retainedBytes, amount: UInt64(value.utf8.count))
                }
                if let owner = sequence.ownedBy {
                    try validation.ledger.consume(.totalNodes)
                    try validation.ledger.consume(.retainedBytes, amount: UInt64(owner.relationID.utf8.count))
                    try validation.ledger.consume(.retainedBytes, amount: UInt64(owner.columnID.utf8.count))
                }
            case .savepoint(let name), .rollbackTo(let name), .release(let name):
                try validation.ledger.consume(.retainedBytes, amount: UInt64(name.utf8.count))
                guard !name.isEmpty, !name.utf8.contains(0) else {
                    throw .invalidSQLCheckpointName
                }
            }
        }
        try validation.validateParameters(parameters)
        for parameter in parameters {
            if let name = parameter.name {
                try validation.ledger.consume(.retainedBytes, amount: UInt64(name.utf8.count))
            }
        }
    }

    public static func validate(
        _ statement: QueryStatement,
        limits: QueryStructuralLimits = .default
    ) throws(QueryStructuralValidationError) {
        var validation = ValidationTraversal(limits: limits)
        try validation.validate([rootValidationStep(for: statement)])
    }

    public static func validate(
        _ query: SelectQuery,
        limits: QueryStructuralLimits = .default
    ) throws(QueryStructuralValidationError) {
        var validation = ValidationTraversal(limits: limits)
        try validation.validate([.select(query, depth: 0)])
    }

    public static func validate(
        _ pattern: GraphPattern,
        limits: QueryStructuralLimits = .default
    ) throws(QueryStructuralValidationError) {
        var validation = ValidationTraversal(limits: limits)
        try validation.validate([.graphPattern(pattern, depth: 0)])
    }

    public static func validate(
        _ expression: Expression,
        limits: QueryStructuralLimits = .default
    ) throws(QueryStructuralValidationError) {
        var validation = ValidationTraversal(limits: limits)
        try validation.validate([.expression(expression, depth: 0)])
    }

    public static func validate(
        _ aggregate: AggregateFunction,
        limits: QueryStructuralLimits = .default
    ) throws(QueryStructuralValidationError) {
        var validation = ValidationTraversal(limits: limits)
        try validation.validate([.aggregate(aggregate, depth: 0)])
    }

    public static func validate(
        _ request: SPARQLUpdateRequest,
        limits: QueryStructuralLimits = .default
    ) throws(QueryStructuralValidationError) {
        var validation = ValidationTraversal(limits: limits)
        try validation.validate([.sparqlUpdateRequest(request, depth: 0)])
    }

    /// Validates parameter payloads before recursive binding begins.
    public static func validate(
        parameters: [QueryParameter],
        limits: QueryStructuralLimits = .default
    ) throws(QueryStructuralValidationError) {
        var validation = ValidationTraversal(limits: limits)
        try validation.validateParameters(parameters)
    }

    static func validateBoundStructure(
        _ statement: QueryStatement,
        positionalParameters: [UInt32: QueryParameter],
        namedParameters: [String: QueryParameter],
        limits: QueryStructuralLimits
    ) throws(QueryStructuralValidationError) -> QueryParameterReference? {
        var validation = ValidationTraversal(
            limits: limits,
            parameterValues: ParameterValues(
                positions: positionalParameters,
                names: namedParameters
            )
        )
        try validation.validate([rootValidationStep(for: statement)])
        return validation.firstMissingParameter
    }

    private static func rootValidationStep(
        for statement: QueryStatement, depth: UInt64 = 0
    ) -> ValidationStep {
        switch statement {
        case .with(let value): return .sqlWith(value, depth: depth)
        case .merge(let value): return .merge(value, depth: depth)
        case .truncate(let value): return .truncate(value, depth: depth)
        case .select(let query):
            return .select(query, depth: depth)
        case .insert(let query):
            return .insert(query, depth: depth)
        case .update(let query):
            return .sqlUpdate(query, depth: depth)
        case .delete(let query):
            return .delete(query, depth: depth)
        case .createGraph(let statement):
            return .createGraph(statement, depth: depth)
        case .dropGraph:
            return .dropGraph(depth: depth)
        case .sparqlUpdate(let request):
            return .sparqlUpdateRequest(request, depth: depth)
        case .construct(let query):
            return .construct(query, depth: depth)
        case .ask(let query):
            return .ask(query, depth: depth)
        case .describe(let query):
            return .describe(query, depth: depth)
        }
    }
}

private extension QueryStructuralValidator {
    /// Indexed input cursors keep the validation work stack independent of collection width.
    enum ValidationCollection {
        case namedStatements([SQLNamedStatement])
        case mergeClauses([SQLMergeClause])
        case tables([TableRef])
        case terms([SPARQLTerm])
        case vertices([VertexTableDefinition])
        case edges([EdgeTableDefinition])
        case mappings([KeyColumnMapping])
        case labels([LabelExpression])
        case fusionStages([FusionStageSource])
        case fusionInputs([FusionInput])
        case groupings([GroupingElement])
        case groupingSets([[GroupingElement]])
        case groupingRows([[Expression]])
        case windows([NamedWindow])
        case graphColumns([GraphTableColumn])
        case paths([PathPattern])
        case elements([PathElement])
        case properties([PropertyBinding])
        case basic([BasicGraphPatternElement])
        case aggregates([AggregateBinding])
        case literals([Literal])
        case boundValues([FieldValue])
        case fieldValues([FieldValue])
        case identifiers([ReferenceIdentifier])
        case operations([SPARQLUpdateOperation])
        case assignments([Assignment])
        case triples([TriplePattern])
        case quads([Quad])
        case fields([(key: String, value: FieldValue)])
        case parameters([QueryParameter])
        case optionalLiterals([Literal?])
        case insertRows([[Expression]])
        case sparqlRows([[Literal?]])
        case casePairs([CaseWhenPair])
        var count: Int {
            switch self {
            case .groupings(let values): return values.count
            case .groupingSets(let values): return values.count
            case .groupingRows(let values): return values.count
            case .windows(let values): return values.count
            case .namedStatements(let values): return values.count
            case .mergeClauses(let values): return values.count
            case .tables(let values): return values.count
            case .terms(let values): return values.count
            case .vertices(let values): return values.count
            case .edges(let values): return values.count
            case .mappings(let values): return values.count
            case .labels(let values): return values.count
            case .fusionStages(let values): return values.count
            case .fusionInputs(let values): return values.count
            case .graphColumns(let values): return values.count
            case .paths(let values): return values.count
            case .elements(let values): return values.count
            case .properties(let values): return values.count
            case .basic(let values): return values.count
            case .aggregates(let values): return values.count
            case .literals(let values): return values.count
            case .boundValues(let values): return values.count
            case .fieldValues(let values): return values.count
            case .identifiers(let values): return values.count
            case .operations(let values): return values.count
            case .assignments(let values): return values.count
            case .triples(let values): return values.count
            case .quads(let values): return values.count
            case .fields(let values): return values.count
            case .parameters(let values): return values.count
            case .optionalLiterals(let values): return values.count
            case .insertRows(let values): return values.count
            case .sparqlRows(let values): return values.count
            case .casePairs(let values): return values.count
            }
        }
        func child(at index: Int, depth: UInt64) -> ValidationStep? {
            switch self {
            case .groupings(let values): return .grouping(values[index], depth: depth)
            case .windows(let values): return .namedWindow(values[index], depth: depth)
            case .groupingSets, .groupingRows: return nil
            case .namedStatements(let values): return .namedStatement(values[index], depth: depth)
            case .mergeClauses(let values): return .mergeClause(values[index], depth: depth)
            case .tables(let values): return .table(values[index], depth: depth)
            case .terms(let values):
                return .term(values[index], depth: depth)
            case .vertices(let values):
                return .vertexDefinition(values[index], depth: depth)
            case .edges(let values):
                return .edgeDefinition(values[index], depth: depth)
            case .mappings(let values):
                return .keyColumnMapping(values[index], depth: depth)
            case .labels(let values):
                return .labelExpression(values[index], depth: depth)
            case .fusionStages(let values):
                return .fusionStage(values[index], depth: depth)
            case .fusionInputs(let values):
                return .fusionInput(values[index], depth: depth)
            case .graphColumns(let values):
                return .graphTableColumn(values[index], depth: depth)
            case .paths(let values):
                return .pathPattern(values[index], depth: depth)
            case .elements(let values):
                return .pathElement(values[index], depth: depth)
            case .properties(let values):
                return .propertyBinding(values[index], depth: depth)
            case .basic(let values):
                return .basicGraphPatternElement(values[index], depth: depth)
            case .aggregates(let values):
                return .aggregateBinding(values[index], depth: depth)
            case .literals(let values):
                return .literal(values[index], depth: depth)
            case .boundValues(let values):
                return .boundParameterLiteral(values[index], depth: depth)
            case .fieldValues(let values):
                return .fieldValue(values[index], depth: depth)
            case .identifiers(let values):
                return .persistableIdentifier(values[index], depth: depth)
            case .operations(let values):
                return .sparqlUpdateOperation(values[index], depth: depth)
            case .assignments(let values):
                return .assignment(values[index], depth: depth)
            case .triples(let values):
                return .triple(values[index], depth: depth)
            case .quads(let values):
                return .quad(values[index], depth: depth)
            case .fields(let values):
                return .fieldValue(values[index].value, depth: depth)
            case .parameters(let values):
                return .queryValue(values[index].value, values[index].type, depth: depth)
            case .optionalLiterals(let values):
                guard let value = values[index] else { return nil }
                return .literal(value, depth: depth)
            case .insertRows, .sparqlRows, .casePairs: return nil
            }
        }
    }

    enum ValidationStep {
        case collectionCursor(ValidationCollection, Int, depth: UInt64)
        case expressionsCursor([Expression], Int, depth: UInt64)
        case projectionCursor([ProjectionItem], Int, depth: UInt64)
        case sortCursor([SortKey], Int, depth: UInt64)
        case cteCursor([NamedSubquery], Int, depth: UInt64)
        case rowsCursor([[Expression]], Int, depth: UInt64)
        case valueRow([Expression], depth: UInt64)
        case select(SelectQuery, depth: UInt64)
        case construct(ConstructQuery, depth: UInt64)
        case ask(AskQuery, depth: UInt64)
        case describe(DescribeQuery, depth: UInt64)
        case sqlWith(SQLWithStatement, depth: UInt64)
        case namedStatement(SQLNamedStatement, depth: UInt64)
        case merge(MergeQuery, depth: UInt64)
        case mergeClause(SQLMergeClause, depth: UInt64)
        case truncate(TruncateQuery, depth: UInt64)
        case table(TableRef, depth: UInt64)
        case conflictTarget(SQLConflictTarget, depth: UInt64)
        case insert(InsertQuery, depth: UInt64)
        case insertSource(InsertSource, depth: UInt64)
        case conflictAction(OnConflictAction, depth: UInt64)
        case sqlUpdate(UpdateQuery, depth: UInt64)
        case delete(DeleteQuery, depth: UInt64)
        case createGraph(CreateGraphStatement, depth: UInt64)
        case dropGraph(depth: UInt64)
        case vertexDefinition(VertexTableDefinition, depth: UInt64)
        case edgeDefinition(EdgeTableDefinition, depth: UInt64)
        case vertexReference(VertexReference, depth: UInt64)
        case keyColumnMapping(KeyColumnMapping, depth: UInt64)
        case labelExpression(LabelExpression, depth: UInt64)
        case propertiesSpec(PropertiesSpec, depth: UInt64)
        case source(DataSource, depth: UInt64, permitsSet: Bool = false)
        case accessPath(AccessPath, depth: UInt64)
        case indexSource(IndexScanSource, depth: UInt64)
        case fusionStage(FusionStageSource, depth: UInt64)
        case fusionInput(FusionInput, depth: UInt64)
        case fusionIndexSource(FusionIndexSource, depth: UInt64)
        case fusionConnectedSource(FusionConnectedSource, depth: UInt64)
        case graphTableSource(GraphTableSource, depth: UInt64)
        case graphTableColumn(GraphTableColumn, depth: UInt64)
        case matchPattern(MatchPattern, depth: UInt64)
        case pathPattern(PathPattern, depth: UInt64)
        case pathElement(PathElement, depth: UInt64)
        case nodePattern(NodePattern, depth: UInt64)
        case edgePattern(EdgePattern, depth: UInt64)
        case propertyBinding(PropertyBinding, depth: UInt64)
        case projectionItem(ProjectionItem, depth: UInt64)
        case assignment(Assignment, depth: UInt64)
        case sortKey(SortKey, depth: UInt64)
        case cteSearch(CTESearchClause, depth: UInt64)
        case cteCycle(CTECycleClause, depth: UInt64)
        case namedSubquery(NamedSubquery, depth: UInt64)
        case graphPattern(GraphPattern, depth: UInt64)
        case basicGraphPatternElement(
            BasicGraphPatternElement,
            depth: UInt64
        )
        case expression(Expression, depth: UInt64)
        case grouping(GroupingElement, depth: UInt64)
        case sqlAggregate(SQLAggregateCall, depth: UInt64)
        case window(WindowCall, depth: UInt64)
        case specification(WindowSpecification, depth: UInt64)
        case namedWindow(NamedWindow, depth: UInt64)
        case frame(WindowFrame, depth: UInt64)
        case bound(WindowFrameBound, depth: UInt64)
        case aggregate(AggregateFunction, depth: UInt64)
        case aggregateBinding(AggregateBinding, depth: UInt64)
        case dataType(DataType, depth: UInt64)
        case term(SPARQLTerm, depth: UInt64)
        case literal(Literal, depth: UInt64)
        case queryValue(QueryValue, QueryColumnType?, depth: UInt64)
        case columnType(QueryColumnType, depth: UInt64)
        case boundParameterLiteral(FieldValue, depth: UInt64)
        case fieldValue(FieldValue, depth: UInt64)
        case persistableIdentifier(ReferenceIdentifier, depth: UInt64)
        case rdfTerm(RDFTerm, depth: UInt64)
        case propertyPath(PropertyPath, depth: UInt64)
        case triple(TriplePattern, depth: UInt64)
        case quad(Quad, depth: UInt64)
        case modifiers(SPARQLSolutionModifiers, depth: UInt64)
        case sparqlUpdateRequest(SPARQLUpdateRequest, depth: UInt64)
        case sparqlUpdateOperation(SPARQLUpdateOperation, depth: UInt64)
    }

    struct ParameterValues {
        let positions: [UInt32: QueryParameter]
        let names: [String: QueryParameter]

        func value(for reference: QueryParameterReference) -> QueryParameter? {
            switch reference {
            case .position(let position):
                return positions[position]
            case .name(let name):
                return names[name]
            }
        }
    }

    struct ValidationTraversal {
        let limits: QueryStructuralLimits
        let parameterValues: ParameterValues?
        var firstMissingParameter: QueryParameterReference?
        var ledger: QueryStructuralResourceLedger

        init(limits: QueryStructuralLimits) {
            self.limits = limits
            self.parameterValues = nil
            self.ledger = QueryStructuralResourceLedger(limits: limits)
        }

        init(
            limits: QueryStructuralLimits,
            parameterValues: ParameterValues
        ) {
            self.limits = limits
            self.parameterValues = parameterValues
            self.ledger = QueryStructuralResourceLedger(limits: limits)
        }

        mutating func validate(
            _ initialValidationSteps: consuming [ValidationStep]
        ) throws(QueryStructuralValidationError) {
            var validationSteps = consume initialValidationSteps
            while let validationStep = validationSteps.popLast() {
                let depth = depth(of: validationStep)
                let isCursor: Bool
                switch validationStep {
                case .collectionCursor, .expressionsCursor, .projectionCursor, .sortCursor, .cteCursor, .rowsCursor: isCursor = true
                default: isCursor = false
                }
                if !isCursor { try ledger.validateNestingDepth(depth) }
                if isCursor {
                } else if case .queryValue(.primitive, _, _) = validationStep {
                    // The existing primitive traversal owns this node.
                } else {
                    try ledger.consume(.totalNodes)
                }
                let childDepth = isCursor ? depth : try nextDepth(after: depth)

                switch validationStep {
                case .expression, .grouping, .sqlAggregate, .window, .namedWindow,
                     .specification, .frame, .bound, .aggregate, .aggregateBinding,
                     .dataType, .term, .columnType, .queryValue, .literal,
                     .boundParameterLiteral, .fieldValue, .persistableIdentifier, .rdfTerm, .propertyPath,
                     .triple, .quad, .modifiers, .sparqlUpdateRequest, .sparqlUpdateOperation:
                    try validateValueStep(validationStep, depth: depth, childDepth: childDepth, steps: &validationSteps)
                case .collectionCursor, .expressionsCursor, .projectionCursor, .sortCursor, .cteCursor,
                     .rowsCursor, .valueRow, .select, .construct, .ask,
                     .describe, .sqlWith, .namedStatement, .merge, .mergeClause, .truncate, .table, .conflictTarget, .insert, .insertSource, .conflictAction, .sqlUpdate,
                     .delete, .createGraph, .dropGraph, .vertexDefinition, .edgeDefinition,
                     .vertexReference, .keyColumnMapping, .labelExpression, .propertiesSpec, .source,
                     .accessPath, .indexSource, .fusionStage, .fusionInput, .fusionIndexSource,
                     .fusionConnectedSource, .graphTableSource, .graphTableColumn, .matchPattern, .pathPattern,
                     .pathElement, .nodePattern, .edgePattern, .propertyBinding, .projectionItem,
                     .assignment, .sortKey, .cteSearch, .cteCycle, .namedSubquery, .graphPattern, .basicGraphPatternElement:
                    try validateDeclarationStep(validationStep, depth: depth, childDepth: childDepth, steps: &validationSteps)
                }
            }
        }

        // Separate case temporaries from the ledger driver on the fixed WASM stack.
        @inline(never)
        private mutating func validateDeclarationStep(
            _ validationStep: consuming ValidationStep, depth: UInt64, childDepth: UInt64,
            steps validationSteps: inout [ValidationStep]
        ) throws(QueryStructuralValidationError) {
            switch consume validationStep {
            case .collectionCursor(let collection, let index, _):
                guard index < collection.count else { return }
                validationSteps.append(.collectionCursor(collection, index + 1, depth: depth))
                switch collection {
                case .groupingRows(let rows):
                    try consumeCollection(rows[index].count)
                    validationSteps.append(.expressionsCursor(rows[index], 0, depth: depth))
                case .groupingSets(let sets):
                    try consumeCollection(sets[index].count)
                    validationSteps.append(.collectionCursor(.groupings(sets[index]), 0, depth: depth))
                case .insertRows(let rows):
                    try consumeCollection(rows[index].count)
                    validationSteps.append(.expressionsCursor(rows[index], 0, depth: depth))
                case .sparqlRows(let rows):
                    try ledger.consume(.valuesCells, amount: UInt64(rows[index].count))
                    try consumeCollection(rows[index].count)
                    validationSteps.append(.collectionCursor(.optionalLiterals(rows[index]), 0, depth: depth))
                case .casePairs(let pairs):
                    validationSteps.append(.expression(pairs[index].result, depth: depth))
                    validationSteps.append(.expression(pairs[index].condition, depth: depth))
                default:
                    if let child = collection.child(at: index, depth: depth) { validationSteps.append(child) }
                }
            case .expressionsCursor(let values, let index, _):
                guard index < values.count else { return }
                validationSteps.append(.expressionsCursor(values, index + 1, depth: depth))
                validationSteps.append(.expression(values[index], depth: depth))
            case .projectionCursor(let values, let index, _):
                guard index < values.count else { return }
                validationSteps.append(.projectionCursor(values, index + 1, depth: depth))
                validationSteps.append(.projectionItem(values[index], depth: depth))
            case .sortCursor(let values, let index, _):
                guard index < values.count else { return }
                validationSteps.append(.sortCursor(values, index + 1, depth: depth))
                validationSteps.append(.sortKey(values[index], depth: depth))
            case .cteCursor(let values, let index, _):
                guard index < values.count else { return }
                validationSteps.append(.cteCursor(values, index + 1, depth: depth))
                validationSteps.append(.namedSubquery(values[index], depth: depth))
            case .rowsCursor(let values, let index, _):
                guard index < values.count else { return }
                validationSteps.append(.rowsCursor(values, index + 1, depth: depth))
                validationSteps.append(.valueRow(values[index], depth: depth))
            case .valueRow(let values, _):
                try ledger.consume(.valuesCells, amount: UInt64(values.count))
                try consumeCollection(values.count)
                appendExpressions(values, depth: childDepth, to: &validationSteps)
            case .select(let query, _):
                if case .setOperation = query.source {
                    guard query.projection == [.wildcard()], query.quantifier == .all,
                          query.filter == nil, query.groupBy == nil, query.having == nil,
                          query.accessPath == nil, query.windows.isEmpty, !query.reduced, query.dataset == .implicit else {
                        throw .invalidSetQueryEnvelope
                    }
                }
                try appendDataset(query.dataset)
                if case .count(.expression(let limit), _) = query.pagination.limit {
                    validationSteps.append(.expression(limit, depth: childDepth))
                }
                if case .expression(let offset) = query.pagination.offset {
                    validationSteps.append(.expression(offset, depth: childDepth))
                }
                if let orderBy = query.orderBy {
                    try consumeCollection(orderBy.count)
                    appendSortKeys(orderBy, depth: childDepth, to: &validationSteps)
                }
                if case .distinctOn(let keys) = query.quantifier {
                    guard !keys.isEmpty else { throw .emptyDistinctOn }
                    try consumeCollection(keys.count)
                    appendExpressions(keys, depth: childDepth, to: &validationSteps)
                }
                try consumeCollection(query.windows.count)
                validationSteps.append(.collectionCursor(.windows(query.windows), 0, depth: childDepth))
                if let having = query.having { validationSteps.append(.expression(having, depth: childDepth)) }
                if let groupBy = query.groupBy {
                    try consumeCollection(groupBy.count)
                    validationSteps.append(.collectionCursor(.groupings(groupBy), 0, depth: childDepth))
                }
                if let filter = query.filter { validationSteps.append(.expression(filter, depth: childDepth)) }
                validationSteps.append(.source(query.source, depth: childDepth, permitsSet: true))
                if let accessPath = query.accessPath { validationSteps.append(.accessPath(accessPath, depth: childDepth)) }
                try consumeCollection(query.projection.count)
                appendProjectionItems(query.projection, depth: childDepth, to: &validationSteps)
                if let subqueries = query.subqueries {
                    try consumeCollection(subqueries.count)
                    validationSteps.append(.cteCursor(subqueries, 0, depth: childDepth))
                }

            case .construct(let query, _):
                try appendDataset(query.dataset)
                try consumeCollection(query.template.count)
                appendTriples(query.template, depth: childDepth, to: &validationSteps)
                validationSteps.append(.modifiers(query.modifiers, depth: childDepth))
                validationSteps.append(.graphPattern(query.pattern, depth: childDepth))

            case .ask(let query, _):
                try appendDataset(query.dataset)
                validationSteps.append(.modifiers(query.modifiers, depth: childDepth))
                validationSteps.append(.graphPattern(query.pattern, depth: childDepth))

            case .describe(let query, _):
                try appendDataset(query.dataset)
                validationSteps.append(.modifiers(query.modifiers, depth: childDepth))
                if let pattern = query.pattern {
                    validationSteps.append(.graphPattern(pattern, depth: childDepth))
                }
                if case .resources(let first, let additional) = query.selection {
                    try consumeCollection(additional.count)
                    validationSteps.append(.collectionCursor(.terms(additional), 0, depth: childDepth))
                    validationSteps.append(.term(first, depth: childDepth))
                }

            case .sqlWith(let value, _):
                guard !value.statements.isEmpty else { throw .invalidSQLMutation("Empty WITH definitions") }
                try consumeCollection(value.statements.count)
                validationSteps.append(QueryStructuralValidator.rootValidationStep(for: value.body, depth: childDepth))
                validationSteps.append(.collectionCursor(.namedStatements(value.statements), 0, depth: childDepth))
            case .namedStatement(let value, _):
                try admitMutationName(value.name)
                if let columns = value.columns { try admitMutationNames(columns) }
                if let search = value.search { try consumeCollection(search.columns.count) }
                if let cycle = value.cycle { try consumeCollection(cycle.columns.count) }
                try QueryStructuralValidator.validate(value)
                if let search = value.search {
                    validationSteps.append(.cteSearch(search, depth: childDepth))
                }
                if let cycle = value.cycle {
                    validationSteps.append(.cteCycle(cycle, depth: childDepth))
                }
                validationSteps.append(QueryStructuralValidator.rootValidationStep(for: value.statement, depth: childDepth))
            case .merge(let value, _):
                guard !value.clauses.isEmpty else { throw .invalidSQLMutation("Empty MERGE clauses") }
                try admitMutationTable(value.target)
                try appendTablePartitions(value.target, depth: childDepth, to: &validationSteps)
                try admitMutationReturning(value.returning, aliases: value.returningAliases)
                if let items = value.returning { try consumeCollection(items.count); appendProjectionItems(items, depth: childDepth, to: &validationSteps) }
                try consumeCollection(value.clauses.count)
                validationSteps.append(.collectionCursor(.mergeClauses(value.clauses), 0, depth: childDepth))
                validationSteps.append(.expression(value.condition, depth: childDepth))
                validationSteps.append(.source(value.source, depth: childDepth))
            case .mergeClause(let value, _):
                if let condition = value.condition { validationSteps.append(.expression(condition, depth: childDepth)) }
                switch value.action {
                case .insert(let columns, let values, _):
                    if let columns { try admitMutationNames(columns) }
                    if let values {
                        guard !values.isEmpty, columns == nil || columns?.count == values.count else { throw .invalidSQLMutation("Invalid MERGE INSERT arity") }
                        try consumeCollection(values.count)
                        appendExpressions(values, depth: childDepth, to: &validationSteps)
                    } else if columns != nil { throw .invalidSQLMutation("DEFAULT VALUES cannot specify columns") }
                case .update(let assignments):
                    guard !assignments.isEmpty else { throw .invalidSQLMutation("Empty MERGE assignments") }
                    try consumeCollection(assignments.count)
                    appendAssignments(assignments, depth: childDepth, to: &validationSteps)
                case .delete, .doNothing: break
                }
            case .truncate(let value, _):
                guard !value.tables.isEmpty else { throw .invalidSQLMutation("Empty TRUNCATE targets") }
                try consumeCollection(value.tables.count)
                validationSteps.append(.collectionCursor(.tables(value.tables), 0, depth: childDepth))
            case .table(let table, _):
                try admitMutationTable(table)
                guard table.alias == nil else { throw .invalidSQLMutation("TRUNCATE target cannot have an alias") }
                try appendTablePartitions(table, depth: childDepth, to: &validationSteps)
            case .conflictTarget(let target, _):
                switch target {
                case .columns(let columns, let predicate):
                    try admitMutationNames(columns)
                    if let predicate { validationSteps.append(.expression(predicate, depth: childDepth)) }
                case .constraint(let name): try admitMutationName(name)
                }
            case .insert(let query, _):
                try admitMutationReturning(query.returning, aliases: query.returningAliases)
                if let target = query.conflictTarget {
                    guard query.onConflict != nil else { throw .invalidSQLMutation("Conflict target requires action") }
                    validationSteps.append(.conflictTarget(target, depth: childDepth))
                }
                if case .doUpdate = query.onConflict, query.conflictTarget == nil { throw .invalidSQLMutation("Conflict UPDATE requires target") }
                if case .values(let rows) = query.source {
                    guard let width = rows.first?.count, width > 0,
                          rows.allSatisfy({ $0.count == width }), query.columns == nil || query.columns?.count == width else { throw .invalidSQLMutation("Invalid INSERT VALUES arity") }
                }
                try admitMutationTable(query.target)
                try appendTablePartitions(query.target, depth: childDepth, to: &validationSteps)
                if let columns = query.columns { try admitMutationNames(columns) }
                if let returning = query.returning {
                    try consumeCollection(returning.count)
                    appendProjectionItems(returning, depth: childDepth, to: &validationSteps)
                }
                if let onConflict = query.onConflict {
                    validationSteps.append(.conflictAction(onConflict, depth: childDepth))
                }
                validationSteps.append(.insertSource(query.source, depth: childDepth))

            case .insertSource(let source, _):
                switch source {
                case .values(let rows):
                    try consumeCollection(rows.count)
                    validationSteps.append(.collectionCursor(.insertRows(rows), 0, depth: childDepth))
                case .select(let query):
                    validationSteps.append(.select(query, depth: childDepth))
                case .defaultValues:
                    break
                }

            case .conflictAction(let action, _):
                switch action {
                case .doNothing:
                    break
                case .doUpdate(let assignments, let predicate):
                    guard !assignments.isEmpty else { throw .invalidSQLMutation("Empty conflict assignments") }
                    try consumeCollection(assignments.count)
                    appendAssignments(assignments, depth: childDepth, to: &validationSteps)
                    if let predicate {
                        validationSteps.append(.expression(predicate, depth: childDepth))
                    }
                }

            case .sqlUpdate(let query, _):
                guard !query.assignments.isEmpty else { throw .invalidSQLMutation("Empty UPDATE assignments") }
                try admitMutationReturning(query.returning, aliases: query.returningAliases)
                try admitMutationTable(query.target)
                try appendTablePartitions(query.target, depth: childDepth, to: &validationSteps)
                try consumeCollection(query.assignments.count)
                appendAssignments(query.assignments, depth: childDepth, to: &validationSteps)
                if let source = query.from {
                    validationSteps.append(.source(source, depth: childDepth))
                }
                if let filter = query.filter {
                    validationSteps.append(.expression(filter, depth: childDepth))
                }
                if let returning = query.returning {
                    try consumeCollection(returning.count)
                    appendProjectionItems(returning, depth: childDepth, to: &validationSteps)
                }

            case .delete(let query, _):
                try admitMutationReturning(query.returning, aliases: query.returningAliases)
                try admitMutationTable(query.target)
                try appendTablePartitions(query.target, depth: childDepth, to: &validationSteps)
                if let source = query.using {
                    validationSteps.append(.source(source, depth: childDepth))
                }
                if let filter = query.filter {
                    validationSteps.append(.expression(filter, depth: childDepth))
                }
                if let returning = query.returning {
                    try consumeCollection(returning.count)
                    appendProjectionItems(returning, depth: childDepth, to: &validationSteps)
                }

            case .createGraph(let statement, _):
                try consumeCollection(statement.vertexTables.count)
                try consumeCollection(statement.edgeTables.count)
                validationSteps.append(.collectionCursor(.edges(statement.edgeTables), 0, depth: childDepth))
                validationSteps.append(.collectionCursor(.vertices(statement.vertexTables), 0, depth: childDepth))

            case .dropGraph:
                break

            case .vertexDefinition(let definition, _):
                try consumeCollection(definition.keyColumns.count)
                if let labelExpression = definition.labelExpression {
                    validationSteps.append(.labelExpression(labelExpression, depth: childDepth))
                }
                if let propertiesSpec = definition.propertiesSpec {
                    validationSteps.append(.propertiesSpec(propertiesSpec, depth: childDepth))
                }

            case .edgeDefinition(let definition, _):
                try consumeCollection(definition.keyColumns.count)
                if let labelExpression = definition.labelExpression {
                    validationSteps.append(.labelExpression(labelExpression, depth: childDepth))
                }
                if let propertiesSpec = definition.propertiesSpec {
                    validationSteps.append(.propertiesSpec(propertiesSpec, depth: childDepth))
                }
                validationSteps.append(
                    .vertexReference(
                        definition.destinationVertex,
                        depth: childDepth
                    )
                )
                validationSteps.append(
                    .vertexReference(
                        definition.sourceVertex,
                        depth: childDepth
                    )
                )

            case .vertexReference(let reference, _):
                try consumeCollection(reference.keyColumns.count)
                validationSteps.append(.collectionCursor(.mappings(reference.keyColumns), 0, depth: childDepth))

            case .keyColumnMapping:
                break

            case .labelExpression(let expression, _):
                switch expression {
                case .single, .column:
                    break
                case .or(let expressions), .and(let expressions):
                    try consumeCollection(expressions.count)
                    validationSteps.append(.collectionCursor(.labels(expressions), 0, depth: childDepth))
                }

            case .propertiesSpec(let specification, _):
                switch specification {
                case .all, PropertiesSpec.none:
                    break
                case .columns(let columns), .allExcept(let columns):
                    try consumeCollection(columns.count)
                }

            case .source(let source, _, let permitsSet):
                switch source {
                case .table(let table):
                    guard table.alias == nil else { throw .sourceAliasInTableReference }
                    try appendTablePartitions(table, depth: childDepth, to: &validationSteps)
                case .logical:
                    break
                case .tableFunction(let source):
                    try QueryStructuralValidator.validate(source)
                    try ledger.consume(.retainedBytes, amount: UInt64(source.function.name.utf8.count))
                    if let schema = source.function.schema {
                        try ledger.consume(.retainedBytes, amount: UInt64(schema.utf8.count))
                    }
                    try consumeCollection(source.function.arguments.count)
                    appendExpressions(source.function.arguments, depth: childDepth, to: &validationSteps)
                case .subquery(let query):
                    validationSteps.append(.select(query, depth: childDepth))
                case .join(let join):
                    if let condition = join.condition {
                        switch condition {
                        case .on(let expression):
                            validationSteps.append(.expression(expression, depth: childDepth))
                        case .using(let columns):
                            try consumeCollection(columns.count)
                        }
                    }
                    validationSteps.append(.source(join.right, depth: childDepth))
                    validationSteps.append(.source(join.left, depth: childDepth))
                case .values(let rows):
                    let hasDirectExpansion = rows.contains { row in
                        row.contains { if case .fieldExpansion = $0 { return true }; return false }
                    }
                    if !hasDirectExpansion, let width = rows.first?.count {
                        for (index, row) in rows.enumerated() where row.count != width {
                            throw .invalidValuesRowArity(row: index, expected: width, actual: row.count)
                        }
                    }
                    try ledger.consume(.valuesRows, amount: UInt64(rows.count))
                    try consumeCollection(rows.count)
                    validationSteps.append(.rowsCursor(rows, 0, depth: childDepth))
                case .aliased(let source, let name, let columns):
                    try ledger.consume(.retainedBytes, amount: UInt64(name.utf8.count))
                    if let columns {
                        try consumeCollection(columns.count)
                        for column in columns { try ledger.consume(.retainedBytes, amount: UInt64(column.utf8.count)) }
                    }
                    validationSteps.append(.source(source, depth: childDepth))
                case .setOperation(_, _, let left, let right):
                    guard permitsSet else { throw .invalidSetQueryEnvelope }
                    validationSteps.append(.select(right, depth: childDepth))
                    validationSteps.append(.select(left, depth: childDepth))
                case .graphTable(let source):
                    validationSteps.append(.graphTableSource(source, depth: childDepth))
                case .graphPattern(let pattern),
                     .namedGraph(_, let pattern),
                     .service(_, let pattern, _):
                    validationSteps.append(.graphPattern(pattern, depth: childDepth))
                #if DATABASE_KIT_MULTI_BASE
                case .base(_, let source):
                    validationSteps.append(
                        .source(source, depth: childDepth)
                    )
                #endif
                }

            case .accessPath(let accessPath, _):
                switch accessPath {
                case .index(let source):
                    validationSteps.append(.indexSource(source, depth: childDepth))
                case .fusion(let source):
                    try consumeCollection(source.stages.count)
                    if case .weighted(let weights) = source.strategy {
                        try consumeCollection(weights.count)
                    }
                    validationSteps.append(.collectionCursor(.fusionStages(source.stages), 0, depth: childDepth))
                }

            case .indexSource(let source, _):
                try appendParameters(
                    source.parameters,
                    depth: childDepth,
                    to: &validationSteps
                )

            case .fusionStage(let stage, _):
                try consumeCollection(stage.inputs.count)
                validationSteps.append(.collectionCursor(.fusionInputs(stage.inputs), 0, depth: childDepth))

            case .fusionInput(let input, _):
                switch input.operation {
                case .index(let source):
                    validationSteps.append(
                        .fusionIndexSource(source, depth: childDepth)
                    )
                case .connected(let source):
                    validationSteps.append(
                        .fusionConnectedSource(source, depth: childDepth)
                    )
                case .filter(let expression):
                    validationSteps.append(.expression(expression, depth: childDepth))
                case .order(let keys):
                    try consumeCollection(keys.count)
                    appendSortKeys(keys, depth: childDepth, to: &validationSteps)
                }

            case .fusionIndexSource(let source, _):
                if case .matching(_, let fields, _) = source.selection {
                    try consumeCollection(fields.count)
                }
                try consumeCollection(source.referencedFields.count)
                try appendParameters(
                    source.parameters,
                    depth: childDepth,
                    to: &validationSteps
                )

            case .fusionConnectedSource(let source, _):
                if case .matching(_, let fields, _) = source.selection {
                    try consumeCollection(fields.count)
                }
                try consumeCollection(source.edgePartitions.count)
                validationSteps.append(.collectionCursor(.fields(source.edgePartitions.fields), 0, depth: childDepth))

            case .graphTableSource(let source, _):
                if let columns = source.columns {
                    try consumeCollection(columns.count)
                    validationSteps.append(.collectionCursor(.graphColumns(columns), 0, depth: childDepth))
                }
                validationSteps.append(.matchPattern(source.matchPattern, depth: childDepth))

            case .graphTableColumn(let column, _):
                validationSteps.append(.expression(column.expression, depth: childDepth))

            case .matchPattern(let pattern, _):
                try consumeCollection(pattern.paths.count)
                if let expression = pattern.where {
                    validationSteps.append(.expression(expression, depth: childDepth))
                }
                validationSteps.append(.collectionCursor(.paths(pattern.paths), 0, depth: childDepth))

            case .pathPattern(let path, _):
                try consumeCollection(path.elements.count)
                validationSteps.append(.collectionCursor(.elements(path.elements), 0, depth: childDepth))

            case .pathElement(let element, _):
                switch element {
                case .node(let node):
                    validationSteps.append(.nodePattern(node, depth: childDepth))
                case .edge(let edge):
                    validationSteps.append(.edgePattern(edge, depth: childDepth))
                case .quantified(let path, _):
                    validationSteps.append(.pathPattern(path, depth: childDepth))
                case .alternation(let paths):
                    try consumeCollection(paths.count)
                    validationSteps.append(.collectionCursor(.paths(paths), 0, depth: childDepth))
                }

            case .nodePattern(let node, _):
                if let labels = node.labels {
                    try consumeCollection(labels.count)
                }
                if let properties = node.properties {
                    try consumeCollection(properties.count)
                    validationSteps.append(.collectionCursor(.properties(properties), 0, depth: childDepth))
                }

            case .edgePattern(let edge, _):
                if let labels = edge.labels {
                    try consumeCollection(labels.count)
                }
                if let properties = edge.properties {
                    try consumeCollection(properties.count)
                    validationSteps.append(.collectionCursor(.properties(properties), 0, depth: childDepth))
                }

            case .propertyBinding(let binding, _):
                validationSteps.append(.expression(binding.value, depth: childDepth))

            case .projectionItem(let projectionItem, _):
                switch projectionItem {
                case .expression(let expression, let alias):
                    if let alias { try ledger.consume(.retainedBytes, amount: UInt64(alias.utf8.count)) }
                    validationSteps.append(.expression(expression, depth: childDepth))
                case .wildcard(let qualifier):
                    if let qualifier { try ledger.consume(.retainedBytes, amount: UInt64(qualifier.utf8.count)) }
                }

            case .assignment(let assignment, _):
                try admitMutationNames(assignment.columns)
                if assignment.columns.count > 1, case .row(let values) = assignment.value, values.count != assignment.columns.count { throw .invalidSQLMutation("Tuple assignment arity mismatch") }
                validationSteps.append(.expression(assignment.value, depth: childDepth))

            case .sortKey(let key, _):
                validationSteps.append(.expression(key.expression, depth: childDepth))

            case .namedSubquery(let subquery, _):
                // Admit key collections before shape validation builds its uniqueness set.
                if let search = subquery.search { try consumeCollection(search.columns.count) }
                if let cycle = subquery.cycle { try consumeCollection(cycle.columns.count) }
                try QueryStructuralValidator.validate(subquery)
                if let columns = subquery.columns { try consumeCollection(columns.count) }
                if let cycle = subquery.cycle { validationSteps.append(.cteCycle(cycle, depth: childDepth)) }
                if let search = subquery.search { validationSteps.append(.cteSearch(search, depth: childDepth)) }
                validationSteps.append(.select(subquery.query, depth: childDepth))

            case .cteSearch(let search, _):
                try ledger.consume(.retainedBytes, amount: UInt64(search.sequenceColumn.utf8.count))
                for column in search.columns { try ledger.consume(.retainedBytes, amount: UInt64(column.utf8.count)) }

            case .cteCycle(let cycle, _):
                try ledger.consume(.retainedBytes, amount: UInt64(cycle.markColumn.utf8.count))
                try ledger.consume(.retainedBytes, amount: UInt64(cycle.pathColumn.utf8.count))
                for column in cycle.columns { try ledger.consume(.retainedBytes, amount: UInt64(column.utf8.count)) }
                if let value = cycle.defaultValue { validationSteps.append(.literal(value, depth: childDepth)) }
                if let value = cycle.markValue { validationSteps.append(.literal(value, depth: childDepth)) }

            case .graphPattern(let pattern, _):
                switch pattern {
                case .basic(let basicGraphPattern):
                    try ledger.consume(.basicGraphPatterns)
                    try consumeCollection(basicGraphPattern.count)
                    validationSteps.append(.collectionCursor(.basic(basicGraphPattern.elements), 0, depth: childDepth))
                case .join(let lhs, let rhs),
                     .optional(let lhs, let rhs),
                     .union(let lhs, let rhs),
                     .minus(let lhs, let rhs),
                     .lateral(let lhs, let rhs):
                    validationSteps.append(.graphPattern(rhs, depth: childDepth))
                    validationSteps.append(.graphPattern(lhs, depth: childDepth))
                case .filter(let pattern, let expression):
                    validationSteps.append(.expression(expression, depth: childDepth))
                    validationSteps.append(.graphPattern(pattern, depth: childDepth))
                case .bind(let pattern, _, let expression):
                    validationSteps.append(.expression(expression, depth: childDepth))
                    validationSteps.append(.graphPattern(pattern, depth: childDepth))
                case .graph(let term, let pattern):
                    validationSteps.append(.graphPattern(pattern, depth: childDepth))
                    validationSteps.append(.term(term, depth: childDepth))
                case .service(_, let pattern, _):
                    validationSteps.append(.graphPattern(pattern, depth: childDepth))
                case .values(let variables, let rows):
                    try ledger.consume(
                        .valuesVariables,
                        amount: UInt64(variables.count)
                    )
                    try ledger.consume(.valuesRows, amount: UInt64(rows.count))
                    try consumeCollection(variables.count)
                    try consumeCollection(rows.count)
                    validationSteps.append(.collectionCursor(.sparqlRows(rows), 0, depth: childDepth))
                case .subquery(let query):
                    validationSteps.append(.select(query, depth: childDepth))
                case .groupBy(let pattern, let expressions, let aggregates):
                    try consumeCollection(expressions.count)
                    try consumeCollection(aggregates.count)
                    validationSteps.append(.collectionCursor(.aggregates(aggregates), 0, depth: childDepth))
                    appendExpressions(expressions, depth: childDepth, to: &validationSteps)
                    validationSteps.append(.graphPattern(pattern, depth: childDepth))
                }

            case .basicGraphPatternElement(let element, let depth):
                switch element {
                case .triple(let triple):
                    // The enum case and its TriplePattern payload represent one
                    // logical graph-pattern node, so the payload remains at the
                    // element depth. Its terms are the nested children.
                    validationSteps.append(.triple(triple, depth: depth))
                case .propertyPath(let pathPattern):
                    validationSteps.append(
                        .term(pathPattern.object, depth: childDepth)
                    )
                    validationSteps.append(
                        .propertyPath(
                            pathPattern.path,
                            depth: childDepth
                        )
                    )
                    validationSteps.append(
                        .term(pathPattern.subject, depth: childDepth)
                    )
                }

            case .expression, .grouping, .sqlAggregate, .window, .namedWindow,
                 .specification, .frame, .bound, .aggregate, .aggregateBinding,
                 .dataType, .term, .columnType, .queryValue, .literal,
                 .boundParameterLiteral, .fieldValue, .persistableIdentifier, .rdfTerm, .propertyPath,
                 .triple, .quad, .modifiers, .sparqlUpdateRequest, .sparqlUpdateOperation:
                throw .unbalancedNesting
            }
        }

        @inline(never)
        private mutating func validateValueStep(
            _ validationStep: consuming ValidationStep, depth: UInt64, childDepth: UInt64,
            steps validationSteps: inout [ValidationStep]
        ) throws(QueryStructuralValidationError) {
            switch consume validationStep {
            case .expression(let expression, _):
                switch expression {
                case .grouping(let arguments):
                    try consumeCollection(arguments.count)
                    appendExpressions(arguments, depth: childDepth, to: &validationSteps)
                case .window(let call): validationSteps.append(.window(call, depth: childDepth))
                case .currentValue(let kind, let precision):
                    guard precision == nil || kind != .date && (0...6).contains(precision!) else {
                        throw .invalidQueryValue(.incompatibleType)
                    }
                case .collectionOperation(_, let lhs, let rhs),
                     .add(let lhs, let rhs), .concatenate(let lhs, let rhs),
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
                     .nullIf(let lhs, let rhs),
                     .isDistinctFrom(let lhs, let rhs, _):
                    validationSteps.append(.expression(rhs, depth: childDepth))
                    validationSteps.append(.expression(lhs, depth: childDepth))
                case .collate(let value, _), .fieldExpansion(let value),
                     .negate(let value),
                     .not(let value),
                     .truthTest(let value, _, _),
                     .isNull(let value),
                     .isNotNull(let value),
                     .isTriple(let value),
                     .subject(let value),
                     .predicate(let value),
                     .object(let value),
                     .regex(let value, _, _):
                    validationSteps.append(.expression(value, depth: childDepth))
                case .field(let value, let name):
                    try ledger.consume(.retainedBytes, amount: UInt64(name.utf8.count))
                    validationSteps.append(.expression(value, depth: childDepth))
                case .wholeRow(let name):
                    try ledger.consume(.retainedBytes, amount: UInt64(name.utf8.count))
                case .arrayAccess(let base, let subscripts):
                    guard (1...6).contains(subscripts.count) else {
                        throw .invalidArrayAccessSubscriptCount(subscripts.count)
                    }
                    try consumeCollection(subscripts.count)
                    for subscriptValue in subscripts.reversed() {
                        switch subscriptValue {
                        case .index(let value): validationSteps.append(.expression(value, depth: childDepth))
                        case .slice(let lower, let upper):
                            if let upper { validationSteps.append(.expression(upper, depth: childDepth)) }
                            if let lower { validationSteps.append(.expression(lower, depth: childDepth)) }
                        }
                    }
                    validationSteps.append(.expression(base, depth: childDepth))
                case .patternMatch(let subject, let pattern, let escape, let kind):
                    guard kind.permitsEscape || escape == nil else { throw .invalidPatternEscape }
                    if let escape { validationSteps.append(.expression(escape, depth: childDepth)) }
                    validationSteps.append(.expression(pattern, depth: childDepth))
                    validationSteps.append(.expression(subject, depth: childDepth))
                case .cast(let value, let targetType):
                    validationSteps.append(.dataType(targetType, depth: childDepth))
                    validationSteps.append(.expression(value, depth: childDepth))
                case .between(let value, let low, let high):
                    validationSteps.append(.expression(high, depth: childDepth))
                    validationSteps.append(.expression(low, depth: childDepth))
                    validationSteps.append(.expression(value, depth: childDepth))
                case .inList(let value, let values),
                     .notInList(let value, let values):
                    try consumeCollection(values.count)
                    appendExpressions(values, depth: childDepth, to: &validationSteps)
                    validationSteps.append(.expression(value, depth: childDepth))
                case .inSubquery(let value, let query):
                    validationSteps.append(.select(query, depth: childDepth))
                    validationSteps.append(.expression(value, depth: childDepth))
                case .aggregate(let aggregate):
                    validationSteps.append(.aggregate(aggregate, depth: childDepth))
                case .function(let function):
                    guard !function.finalArrayIsVariadic || !function.arguments.isEmpty else {
                        throw .emptyVariadicFunctionArguments
                    }
                    if let schema = function.schema {
                        try ledger.consume(.retainedBytes, amount: UInt64(schema.utf8.count))
                    }
                    try consumeCollection(function.arguments.count)
                    appendExpressions(
                        function.arguments,
                        depth: childDepth,
                        to: &validationSteps
                    )
                case .quantifiedComparison(let lhs, _, _, let source):
                    switch source {
                    case .array(let value): validationSteps.append(.expression(value, depth: childDepth))
                    case .subquery(let query): validationSteps.append(.select(query, depth: childDepth))
                    }
                    validationSteps.append(.expression(lhs, depth: childDepth))
                case .caseWhen(let operand, let cases, let elseResult):
                    try consumeCollection(cases.count)
                    if let elseResult {
                        validationSteps.append(.expression(elseResult, depth: childDepth))
                    }
                    validationSteps.append(.collectionCursor(.casePairs(cases), 0, depth: childDepth))
                    if let operand { validationSteps.append(.expression(operand, depth: childDepth)) }
                case .coalesce(let expressions), .array(let expressions), .row(let expressions), .greatest(let expressions), .least(let expressions):
                    try consumeCollection(expressions.count)
                    appendExpressions(expressions, depth: childDepth, to: &validationSteps)
                case .triple(let subject, let predicate, let object):
                    validationSteps.append(.expression(object, depth: childDepth))
                    validationSteps.append(.expression(predicate, depth: childDepth))
                    validationSteps.append(.expression(subject, depth: childDepth))
                case .subquery(let query), .exists(let query), .arraySubquery(let query):
                    validationSteps.append(.select(query, depth: childDepth))
                case .literal(let literal):
                    validationSteps.append(.literal(literal, depth: childDepth))
                case .parameter(let reference):
                    if let parameter = parameterValues?.value(for: reference) {
                        if parameter.type == nil, case .primitive(let value) = parameter.value {
                            let footprint: QueryValueFootprint
                            do { footprint = try QueryValueValidator.measure(parameter.value) }
                            catch { throw .invalidQueryValue(error) }
                            try ledger.consume(.retainedBytes, amount: footprint.retainedByteCount)
                            validationSteps.append(.boundParameterLiteral(value, depth: childDepth))
                        } else {
                            validationSteps.append(.literal(.queryValue(parameter.value, type: parameter.type), depth: childDepth))
                        }
                    } else if parameterValues != nil, firstMissingParameter == nil {
                        firstMissingParameter = reference
                    }
                case .defaultValue, .column, .variable, .bound:
                    break
                }

            case .grouping(let grouping, _):
                switch grouping {
                case .expression(let expression): validationSteps.append(.expression(expression, depth: childDepth))
                case .rollup(let rows), .cube(let rows):
                    try consumeCollection(rows.count)
                    validationSteps.append(.collectionCursor(.groupingRows(rows), 0, depth: childDepth))
                case .groupingSets(let sets):
                    try consumeCollection(sets.count)
                    validationSteps.append(.collectionCursor(.groupingSets(sets), 0, depth: childDepth))
                }
            case .sqlAggregate(let call, _):
                if let schema = call.schema { try ledger.consume(.retainedBytes, amount: UInt64(schema.utf8.count)) }
                try consumeCollection(call.arguments.count)
                appendExpressions(call.arguments, depth: childDepth, to: &validationSteps)
                try consumeCollection(call.orderBy.count)
                appendSortKeys(call.orderBy, depth: childDepth, to: &validationSteps)
                if let filter = call.filter { validationSteps.append(.expression(filter, depth: childDepth)) }
                if let order = call.withinGroup {
                    try consumeCollection(order.count)
                    appendSortKeys(order, depth: childDepth, to: &validationSteps)
                }
            case .window(let call, _):
                switch call.function {
                case .aggregate(let call): validationSteps.append(.sqlAggregate(call, depth: childDepth))
                case .analytic(_, let arguments):
                    try consumeCollection(arguments.count)
                    appendExpressions(arguments, depth: childDepth, to: &validationSteps)
                }
                switch call.reference {
                case .named(let name): try ledger.consume(.retainedBytes, amount: UInt64(name.utf8.count))
                case .specification(let spec): validationSteps.append(.specification(spec, depth: childDepth))
                }
            case .namedWindow(let window, _):
                try ledger.consume(.retainedBytes, amount: UInt64(window.name.utf8.count))
                validationSteps.append(.specification(window.specification, depth: childDepth))
            case .specification(let spec, _):
                if let name = spec.inheritedName { try ledger.consume(.retainedBytes, amount: UInt64(name.utf8.count)) }
                try consumeCollection(spec.partitionBy.count)
                appendExpressions(spec.partitionBy, depth: childDepth, to: &validationSteps)
                try consumeCollection(spec.orderBy.count)
                appendSortKeys(spec.orderBy, depth: childDepth, to: &validationSteps)
                if let frame = spec.frame { validationSteps.append(.frame(frame, depth: childDepth)) }
            case .frame(let frame, _):
                validationSteps.append(.bound(frame.end, depth: childDepth))
                validationSteps.append(.bound(frame.start, depth: childDepth))
            case .bound(let bound, _):
                switch bound {
                case .preceding(let expression), .following(let expression): validationSteps.append(.expression(expression, depth: childDepth))
                case .unboundedPreceding, .currentRow, .unboundedFollowing: break
                }
            case .aggregate(let aggregate, _):
                switch aggregate {
                case .sql(let call): validationSteps.append(.sqlAggregate(call, depth: childDepth))
                case .count(let expression, _):
                    if let expression {
                        validationSteps.append(.expression(expression, depth: childDepth))
                    }
                case .sum(let expression, _),
                     .avg(let expression, _),
                     .min(let expression),
                     .max(let expression),
                     .groupConcat(let expression, _, _),
                     .sample(let expression):
                    validationSteps.append(.expression(expression, depth: childDepth))
                case .arrayAgg(let expression, let orderBy, _):
                    if let orderBy {
                        try consumeCollection(orderBy.count)
                        appendSortKeys(orderBy, depth: childDepth, to: &validationSteps)
                    }
                    validationSteps.append(.expression(expression, depth: childDepth))
                }

            case .aggregateBinding(let binding, _):
                validationSteps.append(.aggregate(binding.aggregate, depth: childDepth))

            case .dataType(let dataType, _):
                switch dataType {
                case .composite(let type):
                    let footprint: QueryValueFootprint
                    do { footprint = try type.measure() } catch { throw .invalidQueryValue(error) }
                    try ledger.consume(.totalNodes, amount: footprint.nodeCount - 1)
                    try ledger.consume(.collectionElements, amount: footprint.collectionElementCount)
                    try ledger.consume(.retainedBytes, amount: footprint.retainedByteCount)
                    let (maximumDepth, overflow) = depth.addingReportingOverflow(footprint.maximumNestingDepth - 1)
                    guard !overflow else { throw .resourceLimitExceeded(resource: .nestingDepth, actual: .max, maximum: limits.maximumNestingDepth) }
                    try ledger.validateNestingDepth(maximumDepth)
                case .custom(_, let schema):
                    if let schema { try ledger.consume(.retainedBytes, amount: UInt64(schema.utf8.count)) }
                case .array(let element):
                    validationSteps.append(.dataType(element, depth: childDepth))
                case .interval:
                    guard QueryValueValidator.accepts(.primitive(.null), type: .sql(dataType)) else {
                        throw .invalidQueryValue(.incompatibleType)
                    }
                case .time(_, let precision), .timestamp(_, let precision):
                    if let precision, !(0...6).contains(precision) {
                        throw .invalidQueryValue(.incompatibleType)
                    }
                default:
                    break
                }

            case .term(let term, _):
                switch term {
                case .tripleTerm(let subject, let predicate, let object):
                    validationSteps.append(.term(object, depth: childDepth))
                    validationSteps.append(.term(predicate, depth: childDepth))
                    validationSteps.append(.term(subject, depth: childDepth))
                case .reifiedTriple(
                    let subject,
                    let predicate,
                    let object,
                    let reifier
                ):
                    try ledger.consume(.reifiedTripleExpansions)
                    validationSteps.append(.term(reifier, depth: childDepth))
                    validationSteps.append(.term(object, depth: childDepth))
                    validationSteps.append(.term(predicate, depth: childDepth))
                    validationSteps.append(.term(subject, depth: childDepth))
                case .literal(let literal):
                    validationSteps.append(.literal(literal, depth: childDepth))
                case .variable, .iri, .blankNode:
                    break
                }

            case .columnType(let type, _):
                if case .sql(let type) = type {
                    validationSteps.append(.dataType(type, depth: childDepth))
                }

            case .queryValue(let value, let type, _):
                if case .primitive(let primitive) = value {
                    if let type, !QueryValueValidator.accepts(value, type: type) {
                        throw .invalidQueryValue(.incompatibleType)
                    }
                    let footprint: QueryValueFootprint
                    do { footprint = try QueryValueValidator.measure(value) }
                    catch { throw .invalidQueryValue(error) }
                    try ledger.consume(.retainedBytes, amount: footprint.retainedByteCount)
                    validationSteps.append(.fieldValue(primitive, depth: depth))
                    if let type { validationSteps.append(.columnType(type, depth: childDepth)) }
                    break
                }
                let valueLimits = QueryValueLimits(
                    maximumRetainedBytes: limits.maximumRetainedBytes,
                    maximumTotalNodes: limits.maximumTotalNodes,
                    maximumNestingDepth: limits.maximumNestingDepth,
                    maximumCollectionElements: limits.maximumCollectionElements
                )
                let footprint: QueryValueFootprint
                do {
                    try QueryValueValidator.validate(value, type: type, limits: valueLimits)
                    footprint = try QueryValueValidator.measure(value)
                } catch {
                    throw .invalidQueryValue(error)
                }
                // This validation step already owns the root node.
                try ledger.consume(.totalNodes, amount: footprint.nodeCount - 1)
                try ledger.consume(.collectionElements, amount: footprint.collectionElementCount)
                try ledger.consume(.retainedBytes, amount: footprint.retainedByteCount)
                let (maximumDepth, overflow) = depth.addingReportingOverflow(footprint.maximumNestingDepth - 1)
                guard !overflow else {
                    throw .resourceLimitExceeded(resource: .nestingDepth, actual: .max, maximum: limits.maximumNestingDepth)
                }
                try ledger.validateNestingDepth(maximumDepth)
                if let type { validationSteps.append(.columnType(type, depth: childDepth)) }

            case .literal(let literal, _):
                switch literal {
                case .string(let value), .sqlUnknownString(let value):
                    try ledger.consume(.retainedBytes, amount: UInt64(value.utf8.count))
                case .binary(let value):
                    guard let bytes = value.retainedByteCount else { throw .invalidQueryValue(.unknownRetainedByteCount) }
                    try ledger.consume(.retainedBytes, amount: UInt64(bytes))
                case .queryValue(let value, let type):
                    validationSteps.append(.queryValue(value, type, depth: childDepth))
                case .array(let values):
                    try consumeCollection(values.count)
                    validationSteps.append(.collectionCursor(.literals(values), 0, depth: childDepth))
                case .rdfTerm(let term):
                    validationSteps.append(.rdfTerm(term, depth: childDepth))
                case .null, .bool, .int, .uint, .decimal, .double,
                     .date, .timestamp, .uuid, .iri, .blankNode,
                     .typedLiteral, .langLiteral, .dirLangLiteral:
                    break
                }

            case .boundParameterLiteral(let value, _):
                switch value {
                case .array(let values):
                    try consumeCollection(values.count)
                    validationSteps.append(.collectionCursor(.boundValues(values), 0, depth: childDepth))
                case .rdfTerm(let term):
                    validationSteps.append(.rdfTerm(term, depth: childDepth))
                case .object(let object):
                    try appendFieldObject(
                        object,
                        depth: childDepth,
                        to: &validationSteps
                    )
                case .reference(let reference):
                    do {
                        try reference.id.validate()
                    } catch let error {
                        throw .invalidReferenceIdentifier(error)
                    }
                    validationSteps.append(
                        .persistableIdentifier(reference.id, depth: childDepth)
                    )
                    try appendFieldObject(
                        reference.partitions,
                        depth: childDepth,
                        to: &validationSteps
                    )
                case .null, .bool,
                     .int8, .int16, .int32, .int64,
                     .uint8, .uint16, .uint32, .uint64,
                     .float32, .float64, .decimal,
                     .string, .bytes, .date, .time, .dateTime, .timestamp,
                     .timeSpan, .calendarPeriod,
                     .geographicPoint, .geographicPosition, .vector, .uuid:
                    break
                }

            case .fieldValue(let value, _):
                switch value {
                case .array(let values):
                    try consumeCollection(values.count)
                    validationSteps.append(.collectionCursor(.fieldValues(values), 0, depth: childDepth))
                case .object(let fields):
                    try appendFieldObject(fields, depth: childDepth, to: &validationSteps)
                case .reference(let identity):
                    do {
                        try identity.id.validate()
                    } catch let error {
                        throw .invalidReferenceIdentifier(error)
                    }
                    validationSteps.append(
                        .persistableIdentifier(identity.id, depth: childDepth)
                    )
                    try appendFieldObject(
                        identity.partitions,
                        depth: childDepth,
                        to: &validationSteps
                    )
                case .rdfTerm(let term):
                    validationSteps.append(.rdfTerm(term, depth: childDepth))
                case .null, .bool,
                     .int8, .int16, .int32, .int64,
                     .uint8, .uint16, .uint32, .uint64,
                     .float32, .float64, .decimal,
                     .string, .bytes, .date, .time, .dateTime, .timestamp,
                     .timeSpan, .calendarPeriod,
                     .geographicPoint, .geographicPosition, .vector, .uuid:
                    break
                }

            case .persistableIdentifier(let identifier, _):
                if case .composite(let components) = identifier {
                    try consumeCollection(components.count)
                    validationSteps.append(.collectionCursor(.identifiers(components), 0, depth: childDepth))
                }

            case .rdfTerm(let term, _):
                if case .tripleTerm(let subject, let predicate, let object) = term {
                    validationSteps.append(.rdfTerm(object, depth: childDepth))
                    validationSteps.append(.rdfTerm(predicate.term, depth: childDepth))
                    validationSteps.append(.rdfTerm(subject.term, depth: childDepth))
                }

            case .propertyPath(let path, _):
                switch path {
                case .inverse(let child),
                     .zeroOrMore(let child),
                     .oneOrMore(let child),
                     .zeroOrOne(let child),
                     .range(let child, _):
                    validationSteps.append(.propertyPath(child, depth: childDepth))
                case .sequence(let lhs, let rhs),
                     .alternative(let lhs, let rhs):
                    validationSteps.append(.propertyPath(rhs, depth: childDepth))
                    validationSteps.append(.propertyPath(lhs, depth: childDepth))
                case .negatedPropertySet(let set):
                    if let forward = set.forward {
                        try consumeCollection(forward.count)
                    }
                    if let inverse = set.inverse {
                        try consumeCollection(inverse.count)
                    }
                case .iri:
                    break
                }

            case .triple(let triple, _):
                try ledger.consume(.triplePatterns)
                validationSteps.append(.term(triple.object, depth: childDepth))
                validationSteps.append(.term(triple.predicate, depth: childDepth))
                validationSteps.append(.term(triple.subject, depth: childDepth))

            case .quad(let quad, _):
                validationSteps.append(.triple(quad.triple, depth: childDepth))
                if let graph = quad.graph {
                    validationSteps.append(.term(graph, depth: childDepth))
                }

            case .modifiers(let modifiers, _):
                try consumeCollection(modifiers.orderBy.count)
                try consumeCollection(modifiers.having.count)
                try consumeCollection(modifiers.groupBy.count)
                appendSortKeys(modifiers.orderBy, depth: childDepth, to: &validationSteps)
                appendExpressions(modifiers.having, depth: childDepth, to: &validationSteps)
                appendExpressions(modifiers.groupBy, depth: childDepth, to: &validationSteps)

            case .sparqlUpdateRequest(let request, _):
                try consumeCollection(request.additionalOperations.count)
                validationSteps.append(.collectionCursor(.operations(request.additionalOperations), 0, depth: childDepth))
                validationSteps.append(
                    .sparqlUpdateOperation(
                        request.firstOperation,
                        depth: childDepth
                    )
                )

            case .sparqlUpdateOperation(let operation, _):
                switch operation {
                case .insertData(let query):
                    try consumeCollection(query.quads.count)
                    appendQuads(query.quads, depth: childDepth, to: &validationSteps)
                case .deleteData(let query):
                    try consumeCollection(query.quads.count)
                    appendQuads(query.quads, depth: childDepth, to: &validationSteps)
                case .modify(let operation):
                    try consumeCollection(operation.using.count)
                    validationSteps.append(
                        .graphPattern(
                            operation.wherePattern,
                            depth: childDepth
                        )
                    )
                    switch operation.action {
                    case .delete(let quads), .insert(let quads):
                        try consumeCollection(quads.count)
                        appendQuads(quads, depth: childDepth, to: &validationSteps)
                    case .deleteAndInsert(let delete, let insert):
                        try consumeCollection(delete.count)
                        try consumeCollection(insert.count)
                        appendQuads(insert, depth: childDepth, to: &validationSteps)
                        appendQuads(delete, depth: childDepth, to: &validationSteps)
                    }
                case .deleteWhere(let query):
                    try consumeCollection(query.pattern.count)
                    appendQuads(query.pattern, depth: childDepth, to: &validationSteps)
                case .load, .clear, .createGraph, .drop, .graphTransfer:
                    break
                }
            case .collectionCursor, .expressionsCursor, .projectionCursor, .sortCursor, .cteCursor,
                 .rowsCursor, .valueRow, .select, .construct, .ask,
                 .describe, .sqlWith, .namedStatement, .merge, .mergeClause, .truncate, .table, .conflictTarget, .insert, .insertSource, .conflictAction, .sqlUpdate,
                 .delete, .createGraph, .dropGraph, .vertexDefinition, .edgeDefinition,
                 .vertexReference, .keyColumnMapping, .labelExpression, .propertiesSpec, .source,
                 .accessPath, .indexSource, .fusionStage, .fusionInput, .fusionIndexSource,
                 .fusionConnectedSource, .graphTableSource, .graphTableColumn, .matchPattern, .pathPattern,
                 .pathElement, .nodePattern, .edgePattern, .propertyBinding, .projectionItem,
                 .assignment, .sortKey, .cteSearch, .cteCycle, .namedSubquery, .graphPattern, .basicGraphPatternElement:
                throw .unbalancedNesting
            }
        }

        mutating func validateParameters(
            _ parameters: [QueryParameter]
        ) throws(QueryStructuralValidationError) {
            try consumeCollection(parameters.count)
            let validationSteps: [ValidationStep] = [.collectionCursor(.parameters(parameters), 0, depth: 0)]
            try validate(consume validationSteps)
        }

        private func depth(of validationStep: ValidationStep) -> UInt64 {
            switch validationStep {
            case .collectionCursor(_, _, let depth), .expressionsCursor(_, _, let depth), .projectionCursor(_, _, let depth),
                 .sortCursor(_, _, let depth), .cteCursor(_, _, let depth), .rowsCursor(_, _, let depth),
                 .valueRow(_, let depth), .select(_, let depth), .construct(_, let depth),
                 .ask(_, let depth), .describe(_, let depth),
                 .sqlWith(_, let depth), .namedStatement(_, let depth), .merge(_, let depth),
                 .mergeClause(_, let depth), .truncate(_, let depth), .table(_, let depth), .conflictTarget(_, let depth),
                 .insert(_, let depth), .insertSource(_, let depth),
                 .conflictAction(_, let depth), .sqlUpdate(_, let depth),
                 .delete(_, let depth), .createGraph(_, let depth),
                 .vertexDefinition(_, let depth),
                 .edgeDefinition(_, let depth),
                 .vertexReference(_, let depth),
                 .keyColumnMapping(_, let depth),
                 .labelExpression(_, let depth),
                 .propertiesSpec(_, let depth), .source(_, let depth, _),
                 .accessPath(_, let depth), .indexSource(_, let depth),
                 .fusionStage(_, let depth), .fusionInput(_, let depth),
                 .fusionIndexSource(_, let depth),
                 .fusionConnectedSource(_, let depth),
                 .graphTableSource(_, let depth),
                 .graphTableColumn(_, let depth),
                 .matchPattern(_, let depth), .pathPattern(_, let depth),
                 .pathElement(_, let depth), .nodePattern(_, let depth),
                 .edgePattern(_, let depth), .propertyBinding(_, let depth),
                 .projectionItem(_, let depth), .assignment(_, let depth),
                 .sortKey(_, let depth), .cteSearch(_, let depth), .cteCycle(_, let depth), .namedSubquery(_, let depth),
                 .graphPattern(_, let depth),
                 .basicGraphPatternElement(_, let depth),
                 .expression(_, let depth),
                 .grouping(_, let depth), .sqlAggregate(_, let depth), .window(_, let depth),
                 .specification(_, let depth), .namedWindow(_, let depth), .frame(_, let depth), .bound(_, let depth),
                 .aggregate(_, let depth), .aggregateBinding(_, let depth),
                 .dataType(_, let depth), .term(_, let depth),
                 .literal(_, let depth),
                 .queryValue(_, _, let depth), .columnType(_, let depth),
                 .boundParameterLiteral(_, let depth),
                 .fieldValue(_, let depth),
                 .persistableIdentifier(_, let depth),
                 .rdfTerm(_, let depth), .propertyPath(_, let depth),
                 .triple(_, let depth), .quad(_, let depth),
                 .modifiers(_, let depth),
                 .sparqlUpdateRequest(_, let depth),
                 .sparqlUpdateOperation(_, let depth), .dropGraph(let depth):
                return depth
            }
        }

        private mutating func admitMutationTable(_ table: TableRef) throws(QueryStructuralValidationError) {
            try admitMutationName(table.table)
            if let name = table.schema { try admitMutationName(name) }
            if let name = table.alias { try admitMutationName(name) }
        }

        private mutating func admitMutationName(_ name: String) throws(QueryStructuralValidationError) {
            guard !name.isEmpty, !name.utf8.contains(0) else { throw .invalidSQLMutation("Invalid mutation identifier") }
            try ledger.consume(.retainedBytes, amount: UInt64(name.utf8.count))
        }

        private mutating func admitMutationNames(_ names: [String]) throws(QueryStructuralValidationError) {
            guard !names.isEmpty else { throw .invalidSQLMutation("Empty mutation target names") }
            try consumeCollection(names.count)
            for name in names { try admitMutationName(name) }
        }

        private mutating func admitMutationReturning(_ items: [ProjectionItem]?, aliases: SQLReturningAliases?) throws(QueryStructuralValidationError) {
            if let items, items.isEmpty { throw .invalidSQLMutation("Empty RETURNING") }
            guard let aliases else { return }
            guard items != nil, aliases.old != nil || aliases.new != nil else { throw .invalidSQLMutation("Invalid RETURNING aliases") }
            if let name = aliases.old { try admitMutationName(name) }
            if let name = aliases.new { try admitMutationName(name) }
        }

        private func nextDepth(
            after depth: UInt64
        ) throws(QueryStructuralValidationError) -> UInt64 {
            let (next, overflow) = depth.addingReportingOverflow(1)
            guard !overflow else {
                throw .resourceLimitExceeded(
                    resource: .nestingDepth,
                    actual: UInt64.max,
                    maximum: limits.maximumNestingDepth
                )
            }
            return next
        }

        private mutating func consumeCollection(
            _ count: Int
        ) throws(QueryStructuralValidationError) {
            try ledger.consume(.collectionElements, amount: UInt64(count))
        }

        private mutating func appendDataset(
            _ dataset: SPARQLDataset
        ) throws(QueryStructuralValidationError) {
            guard case .explicit(let defaultGraphs, let namedGraphs) = dataset else {
                return
            }
            try consumeCollection(defaultGraphs.count)
            try consumeCollection(namedGraphs.count)
        }

        private mutating func appendTablePartitions(
            _ table: TableRef,
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) throws(QueryStructuralValidationError) {
            try appendFieldObject(table.partitions, depth: depth, to: &validationSteps)
        }

        private mutating func appendFieldObject(
            _ object: FieldObject,
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) throws(QueryStructuralValidationError) {
            let fields = object.fields
            try consumeCollection(fields.count)
            validationSteps.append(.collectionCursor(.fields(fields), 0, depth: depth))
        }

        private mutating func appendParameters(
            _ parameters: [String: FieldValue],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) throws(QueryStructuralValidationError) {
            try consumeCollection(parameters.count)
            let orderedParameters = parameters.sorted { lhs, rhs in
                lhs.key < rhs.key
            }
            validationSteps.append(.collectionCursor(.fields(orderedParameters), 0, depth: depth))
        }

        private func appendExpressions(
            _ expressions: [Expression],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) {
            validationSteps.append(.expressionsCursor(expressions, 0, depth: depth))
        }

        private func appendProjectionItems(
            _ items: [ProjectionItem],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) {
            validationSteps.append(.projectionCursor(items, 0, depth: depth))
        }

        private func appendAssignments(
            _ assignments: [Assignment],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) {
            validationSteps.append(.collectionCursor(.assignments(assignments), 0, depth: depth))
        }

        private func appendSortKeys(
            _ keys: [SortKey],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) {
            validationSteps.append(.sortCursor(keys, 0, depth: depth))
        }

        private func appendTriples(
            _ triples: [TriplePattern],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) {
            validationSteps.append(.collectionCursor(.triples(triples), 0, depth: depth))
        }

        private func appendQuads(
            _ quads: [Quad],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) {
            validationSteps.append(.collectionCursor(.quads(quads), 0, depth: depth))
        }
    }
}
