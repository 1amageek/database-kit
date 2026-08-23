import DatabaseTypes

/// Performs bounded, non-recursive validation of canonical QueryIR.
///
/// The explicit validation-step stack ensures adversarial QueryIR cannot exhaust
/// the process stack before semantic validation reports a typed resource error.
public enum QueryStructuralValidator {
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
        positionalParameters: [UInt32: FieldValue],
        namedParameters: [String: FieldValue],
        limits: QueryStructuralLimits
    ) throws(QueryStructuralValidationError) {
        var validation = ValidationTraversal(
            limits: limits,
            parameterValues: ParameterValues(
                positions: positionalParameters,
                names: namedParameters
            )
        )
        try validation.validate([rootValidationStep(for: statement)])
    }

    private static func rootValidationStep(
        for statement: QueryStatement
    ) -> ValidationStep {
        switch statement {
        case .select(let query):
            return .select(query, depth: 0)
        case .insert(let query):
            return .insert(query, depth: 0)
        case .update(let query):
            return .sqlUpdate(query, depth: 0)
        case .delete(let query):
            return .delete(query, depth: 0)
        case .createGraph(let statement):
            return .createGraph(statement, depth: 0)
        case .dropGraph:
            return .dropGraph(depth: 0)
        case .sparqlUpdate(let request):
            return .sparqlUpdateRequest(request, depth: 0)
        case .construct(let query):
            return .construct(query, depth: 0)
        case .ask(let query):
            return .ask(query, depth: 0)
        case .describe(let query):
            return .describe(query, depth: 0)
        }
    }
}

private extension QueryStructuralValidator {
    enum ValidationStep {
        case select(SelectQuery, depth: UInt64)
        case construct(ConstructQuery, depth: UInt64)
        case ask(AskQuery, depth: UInt64)
        case describe(DescribeQuery, depth: UInt64)
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
        case source(DataSource, depth: UInt64)
        case accessPath(AccessPath, depth: UInt64)
        case indexSource(IndexScanSource, depth: UInt64)
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
        case namedSubquery(NamedSubquery, depth: UInt64)
        case graphPattern(GraphPattern, depth: UInt64)
        case basicGraphPatternElement(
            BasicGraphPatternElement,
            depth: UInt64
        )
        case expression(Expression, depth: UInt64)
        case aggregate(AggregateFunction, depth: UInt64)
        case aggregateBinding(AggregateBinding, depth: UInt64)
        case dataType(DataType, depth: UInt64)
        case term(SPARQLTerm, depth: UInt64)
        case literal(Literal, depth: UInt64)
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
        let positions: [UInt32: FieldValue]
        let names: [String: FieldValue]

        func value(for reference: QueryParameterReference) -> FieldValue? {
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
                try ledger.validateNestingDepth(depth)
                try ledger.consume(.totalNodes)
                let childDepth = try nextDepth(after: depth)

                switch validationStep {
                case .select(let query, _):
                    try appendDataset(query.dataset)
                    if let subqueries = query.subqueries {
                        try consumeCollection(subqueries.count)
                        for subquery in subqueries.reversed() {
                            validationSteps.append(.namedSubquery(subquery, depth: childDepth))
                        }
                    }
                    if let orderBy = query.orderBy {
                        try consumeCollection(orderBy.count)
                        appendSortKeys(orderBy, depth: childDepth, to: &validationSteps)
                    }
                    if let having = query.having {
                        validationSteps.append(.expression(having, depth: childDepth))
                    }
                    if let groupBy = query.groupBy {
                        try consumeCollection(groupBy.count)
                        appendExpressions(groupBy, depth: childDepth, to: &validationSteps)
                    }
                    if let filter = query.filter {
                        validationSteps.append(.expression(filter, depth: childDepth))
                    }
                    switch query.projection {
                    case .items(let items), .distinctItems(let items):
                        try consumeCollection(items.count)
                        appendProjectionItems(items, depth: childDepth, to: &validationSteps)
                    case .all, .allFrom:
                        break
                    }
                    if let accessPath = query.accessPath {
                        validationSteps.append(.accessPath(accessPath, depth: childDepth))
                    }
                    validationSteps.append(.source(query.source, depth: childDepth))

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
                        for term in additional.reversed() {
                            validationSteps.append(.term(term, depth: childDepth))
                        }
                        validationSteps.append(.term(first, depth: childDepth))
                    }

                case .insert(let query, _):
                    try appendTablePartitions(query.target, depth: childDepth, to: &validationSteps)
                    if let columns = query.columns {
                        try consumeCollection(columns.count)
                    }
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
                        for row in rows.reversed() {
                            try consumeCollection(row.count)
                            appendExpressions(row, depth: childDepth, to: &validationSteps)
                        }
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
                        try consumeCollection(assignments.count)
                        appendAssignments(assignments, depth: childDepth, to: &validationSteps)
                        if let predicate {
                            validationSteps.append(.expression(predicate, depth: childDepth))
                        }
                    }

                case .sqlUpdate(let query, _):
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
                    for edge in statement.edgeTables.reversed() {
                        validationSteps.append(.edgeDefinition(edge, depth: childDepth))
                    }
                    for vertex in statement.vertexTables.reversed() {
                        validationSteps.append(.vertexDefinition(vertex, depth: childDepth))
                    }

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
                    for mapping in reference.keyColumns.reversed() {
                        validationSteps.append(
                            .keyColumnMapping(mapping, depth: childDepth)
                        )
                    }

                case .keyColumnMapping:
                    break

                case .labelExpression(let expression, _):
                    switch expression {
                    case .single, .column:
                        break
                    case .or(let expressions), .and(let expressions):
                        try consumeCollection(expressions.count)
                        for expression in expressions.reversed() {
                            validationSteps.append(
                                .labelExpression(expression, depth: childDepth)
                            )
                        }
                    }

                case .propertiesSpec(let specification, _):
                    switch specification {
                    case .all, PropertiesSpec.none:
                        break
                    case .columns(let columns), .allExcept(let columns):
                        try consumeCollection(columns.count)
                    }

                case .source(let source, _):
                    switch source {
                    case .table(let table):
                        try appendTablePartitions(table, depth: childDepth, to: &validationSteps)
                    case .logical:
                        break
                    case .subquery(let query, _):
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
                    case .values(let rows, let columnNames):
                        if let columnNames {
                            try ledger.consume(
                                .valuesVariables,
                                amount: UInt64(columnNames.count)
                            )
                            try consumeCollection(columnNames.count)
                        }
                        try ledger.consume(.valuesRows, amount: UInt64(rows.count))
                        try consumeCollection(rows.count)
                        for row in rows.reversed() {
                            try ledger.consume(.valuesCells, amount: UInt64(row.count))
                            try consumeCollection(row.count)
                            for literal in row.reversed() {
                                validationSteps.append(.literal(literal, depth: childDepth))
                            }
                        }
                    case .graphTable(let source):
                        validationSteps.append(.graphTableSource(source, depth: childDepth))
                    case .graphPattern(let pattern),
                         .namedGraph(_, let pattern),
                         .service(_, let pattern, _):
                        validationSteps.append(.graphPattern(pattern, depth: childDepth))
                    case .union(let sources),
                         .unionAll(let sources),
                         .intersect(let sources):
                        try consumeCollection(sources.count)
                        for source in sources.reversed() {
                            validationSteps.append(.source(source, depth: childDepth))
                        }
                    case .except(let lhs, let rhs):
                        validationSteps.append(.source(rhs, depth: childDepth))
                        validationSteps.append(.source(lhs, depth: childDepth))
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
                        try consumeCollection(source.inputs.count)
                        try appendParameters(
                            source.parameters,
                            depth: childDepth,
                            to: &validationSteps
                        )
                        for input in source.inputs.reversed() {
                            validationSteps.append(.indexSource(input, depth: childDepth))
                        }
                    }

                case .indexSource(let source, _):
                    try appendParameters(
                        source.parameters,
                        depth: childDepth,
                        to: &validationSteps
                    )

                case .graphTableSource(let source, _):
                    if let columns = source.columns {
                        try consumeCollection(columns.count)
                        for column in columns.reversed() {
                            validationSteps.append(
                                .graphTableColumn(column, depth: childDepth)
                            )
                        }
                    }
                    validationSteps.append(.matchPattern(source.matchPattern, depth: childDepth))

                case .graphTableColumn(let column, _):
                    validationSteps.append(.expression(column.expression, depth: childDepth))

                case .matchPattern(let pattern, _):
                    try consumeCollection(pattern.paths.count)
                    if let expression = pattern.where {
                        validationSteps.append(.expression(expression, depth: childDepth))
                    }
                    for path in pattern.paths.reversed() {
                        validationSteps.append(.pathPattern(path, depth: childDepth))
                    }

                case .pathPattern(let path, _):
                    try consumeCollection(path.elements.count)
                    for element in path.elements.reversed() {
                        validationSteps.append(.pathElement(element, depth: childDepth))
                    }

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
                        for path in paths.reversed() {
                            validationSteps.append(.pathPattern(path, depth: childDepth))
                        }
                    }

                case .nodePattern(let node, _):
                    if let labels = node.labels {
                        try consumeCollection(labels.count)
                    }
                    if let properties = node.properties {
                        try consumeCollection(properties.count)
                        for property in properties.reversed() {
                            validationSteps.append(
                                .propertyBinding(property, depth: childDepth)
                            )
                        }
                    }

                case .edgePattern(let edge, _):
                    if let labels = edge.labels {
                        try consumeCollection(labels.count)
                    }
                    if let properties = edge.properties {
                        try consumeCollection(properties.count)
                        for property in properties.reversed() {
                            validationSteps.append(
                                .propertyBinding(property, depth: childDepth)
                            )
                        }
                    }

                case .propertyBinding(let binding, _):
                    validationSteps.append(.expression(binding.value, depth: childDepth))

                case .projectionItem(let projectionItem, _):
                    validationSteps.append(
                        .expression(projectionItem.expression, depth: childDepth)
                    )

                case .assignment(let assignment, _):
                    validationSteps.append(.expression(assignment.value, depth: childDepth))

                case .sortKey(let key, _):
                    validationSteps.append(.expression(key.expression, depth: childDepth))

                case .namedSubquery(let subquery, _):
                    if let columns = subquery.columns {
                        try consumeCollection(columns.count)
                    }
                    validationSteps.append(.select(subquery.query, depth: childDepth))

                case .graphPattern(let pattern, _):
                    switch pattern {
                    case .basic(let basicGraphPattern):
                        try ledger.consume(.basicGraphPatterns)
                        try consumeCollection(basicGraphPattern.count)
                        for element in basicGraphPattern.elements.reversed() {
                            validationSteps.append(
                                .basicGraphPatternElement(
                                    element,
                                    depth: childDepth
                                )
                            )
                        }
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
                        for row in rows.reversed() {
                            try ledger.consume(.valuesCells, amount: UInt64(row.count))
                            try consumeCollection(row.count)
                            for literal in row.reversed() {
                                if let literal {
                                    validationSteps.append(.literal(literal, depth: childDepth))
                                }
                            }
                        }
                    case .subquery(let query):
                        validationSteps.append(.select(query, depth: childDepth))
                    case .groupBy(let pattern, let expressions, let aggregates):
                        try consumeCollection(expressions.count)
                        try consumeCollection(aggregates.count)
                        for aggregate in aggregates.reversed() {
                            validationSteps.append(
                                .aggregateBinding(aggregate, depth: childDepth)
                            )
                        }
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

                case .expression(let expression, _):
                    switch expression {
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
                        validationSteps.append(.expression(rhs, depth: childDepth))
                        validationSteps.append(.expression(lhs, depth: childDepth))
                    case .negate(let value),
                         .not(let value),
                         .isNull(let value),
                         .isNotNull(let value),
                         .isTriple(let value),
                         .subject(let value),
                         .predicate(let value),
                         .object(let value),
                         .like(let value, _),
                         .regex(let value, _, _):
                        validationSteps.append(.expression(value, depth: childDepth))
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
                        try consumeCollection(function.arguments.count)
                        appendExpressions(
                            function.arguments,
                            depth: childDepth,
                            to: &validationSteps
                        )
                    case .caseWhen(let cases, let elseResult):
                        try consumeCollection(cases.count)
                        if let elseResult {
                            validationSteps.append(.expression(elseResult, depth: childDepth))
                        }
                        for pair in cases.reversed() {
                            validationSteps.append(.expression(pair.result, depth: childDepth))
                            validationSteps.append(.expression(pair.condition, depth: childDepth))
                        }
                    case .coalesce(let expressions):
                        try consumeCollection(expressions.count)
                        appendExpressions(expressions, depth: childDepth, to: &validationSteps)
                    case .triple(let subject, let predicate, let object):
                        validationSteps.append(.expression(object, depth: childDepth))
                        validationSteps.append(.expression(predicate, depth: childDepth))
                        validationSteps.append(.expression(subject, depth: childDepth))
                    case .subquery(let query), .exists(let query):
                        validationSteps.append(.select(query, depth: childDepth))
                    case .literal(let literal):
                        validationSteps.append(.literal(literal, depth: childDepth))
                    case .parameter(let reference):
                        if let value = parameterValues?.value(for: reference) {
                            validationSteps.append(
                                .boundParameterLiteral(
                                    value,
                                    depth: childDepth
                                )
                            )
                        }
                    case .column, .variable, .bound:
                        break
                    }

                case .aggregate(let aggregate, _):
                    switch aggregate {
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
                    if case .array(let element) = dataType {
                        validationSteps.append(.dataType(element, depth: childDepth))
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

                case .literal(let literal, _):
                    switch literal {
                    case .array(let values):
                        try consumeCollection(values.count)
                        for value in values.reversed() {
                            validationSteps.append(.literal(value, depth: childDepth))
                        }
                    case .rdfTerm(let term):
                        validationSteps.append(.rdfTerm(term, depth: childDepth))
                    case .null, .bool, .int, .uint, .decimal, .double, .string,
                         .date, .timestamp, .binary, .uuid, .iri, .blankNode,
                         .typedLiteral, .langLiteral, .dirLangLiteral:
                        break
                    }

                case .boundParameterLiteral(let value, _):
                    switch value {
                    case .array(let values):
                        try consumeCollection(values.count)
                        for value in values.reversed() {
                            validationSteps.append(
                                .boundParameterLiteral(
                                    value,
                                    depth: childDepth
                                )
                            )
                        }
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
                        for value in values.reversed() {
                            validationSteps.append(.fieldValue(value, depth: childDepth))
                        }
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
                        for component in components.reversed() {
                            validationSteps.append(
                                .persistableIdentifier(component, depth: childDepth)
                            )
                        }
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
                    for operation in request.additionalOperations.reversed() {
                        validationSteps.append(
                            .sparqlUpdateOperation(operation, depth: childDepth)
                        )
                    }
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
                }
            }
        }

        mutating func validateParameters(
            _ parameters: [QueryParameter]
        ) throws(QueryStructuralValidationError) {
            try consumeCollection(parameters.count)
            var validationSteps: [ValidationStep] = []
            validationSteps.reserveCapacity(parameters.count)
            for parameter in parameters.reversed() {
                validationSteps.append(.fieldValue(parameter.value, depth: 0))
            }
            try validate(consume validationSteps)
        }

        private func depth(of validationStep: ValidationStep) -> UInt64 {
            switch validationStep {
            case .select(_, let depth), .construct(_, let depth),
                 .ask(_, let depth), .describe(_, let depth),
                 .insert(_, let depth), .insertSource(_, let depth),
                 .conflictAction(_, let depth), .sqlUpdate(_, let depth),
                 .delete(_, let depth), .createGraph(_, let depth),
                 .vertexDefinition(_, let depth),
                 .edgeDefinition(_, let depth),
                 .vertexReference(_, let depth),
                 .keyColumnMapping(_, let depth),
                 .labelExpression(_, let depth),
                 .propertiesSpec(_, let depth), .source(_, let depth),
                 .accessPath(_, let depth), .indexSource(_, let depth),
                 .graphTableSource(_, let depth),
                 .graphTableColumn(_, let depth),
                 .matchPattern(_, let depth), .pathPattern(_, let depth),
                 .pathElement(_, let depth), .nodePattern(_, let depth),
                 .edgePattern(_, let depth), .propertyBinding(_, let depth),
                 .projectionItem(_, let depth), .assignment(_, let depth),
                 .sortKey(_, let depth), .namedSubquery(_, let depth),
                 .graphPattern(_, let depth),
                 .basicGraphPatternElement(_, let depth),
                 .expression(_, let depth),
                 .aggregate(_, let depth), .aggregateBinding(_, let depth),
                 .dataType(_, let depth), .term(_, let depth),
                 .literal(_, let depth),
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
            for field in fields.reversed() {
                validationSteps.append(.fieldValue(field.value, depth: depth))
            }
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
            for (_, parameter) in orderedParameters.reversed() {
                validationSteps.append(.fieldValue(parameter, depth: depth))
            }
        }

        private func appendExpressions(
            _ expressions: [Expression],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) {
            for expression in expressions.reversed() {
                validationSteps.append(.expression(expression, depth: depth))
            }
        }

        private func appendProjectionItems(
            _ items: [ProjectionItem],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) {
            for projectionItem in items.reversed() {
                validationSteps.append(.projectionItem(projectionItem, depth: depth))
            }
        }

        private func appendAssignments(
            _ assignments: [Assignment],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) {
            for assignment in assignments.reversed() {
                validationSteps.append(.assignment(assignment, depth: depth))
            }
        }

        private func appendSortKeys(
            _ keys: [SortKey],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) {
            for key in keys.reversed() {
                validationSteps.append(.sortKey(key, depth: depth))
            }
        }

        private func appendTriples(
            _ triples: [TriplePattern],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) {
            for triple in triples.reversed() {
                validationSteps.append(.triple(triple, depth: depth))
            }
        }

        private func appendQuads(
            _ quads: [Quad],
            depth: UInt64,
            to validationSteps: inout [ValidationStep]
        ) {
            for quad in quads.reversed() {
                validationSteps.append(.quad(quad, depth: depth))
            }
        }
    }
}
