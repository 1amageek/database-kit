import DatabaseTypes

/// Validates canonical QueryIR representation and request-level SPARQL rules.
///
/// The validator belongs to QueryIR so text parsers and binary callers share
/// one semantic gate. It does not rewrite terms or allocate payload copies.
public enum SPARQLSemanticValidator {
    public static func validate(
        _ statement: QueryStatement,
        limits: QueryStructuralLimits = .default
    ) throws(SPARQLSemanticValidationError) {
        try validateStructure { () throws(QueryStructuralValidationError) in
            try QueryStructuralValidator.validate(statement, limits: limits)
        }
        switch statement {
        case .select(let query):
            try validateSemantics(query)
        case .construct(let query):
            try validateDataset(query.dataset)
            try validateTriples(
                query.template,
                variableContext: nil,
                onBlankNode: { _ in }
            )
            var state = QueryScopeState()
            try state.validate(query.pattern)
            try state.validate(query.modifiers)
        case .ask(let query):
            try validateDataset(query.dataset)
            var state = QueryScopeState()
            try state.validate(query.pattern)
            try state.validate(query.modifiers)
        case .describe(let query):
            try validateDataset(query.dataset)
            switch query.selection {
            case .all:
                break
            case .resources(let first, let additional):
                try validateTerm(
                    first,
                    role: .describeResource,
                    variableContext: nil,
                    onBlankNode: { _ in }
                )
                for term in additional {
                    try validateTerm(
                        term,
                        role: .describeResource,
                        variableContext: nil,
                        onBlankNode: { _ in }
                    )
                }
            }
            var state = QueryScopeState()
            if let pattern = query.pattern {
                try state.validate(pattern)
            }
            try state.validate(query.modifiers)
        case .sparqlUpdate(let request):
            try validateSemantics(request)
        case .insert, .update, .delete, .createGraph, .dropGraph:
            break
        }
    }

    public static func validate(
        _ query: SelectQuery,
        limits: QueryStructuralLimits = .default
    ) throws(SPARQLSemanticValidationError) {
        try validateStructure { () throws(QueryStructuralValidationError) in
            try QueryStructuralValidator.validate(query, limits: limits)
        }
        try validateSemantics(query)
    }

    private static func validateSemantics(
        _ query: SelectQuery
    ) throws(SPARQLSemanticValidationError) {
        var state = QueryScopeState()
        try state.validate(query)
    }

    public static func validate(
        _ pattern: GraphPattern,
        limits: QueryStructuralLimits = .default
    ) throws(SPARQLSemanticValidationError) {
        try validateStructure { () throws(QueryStructuralValidationError) in
            try QueryStructuralValidator.validate(pattern, limits: limits)
        }
        var state = QueryScopeState()
        try state.validate(pattern)
    }

    public static func validate(
        _ request: SPARQLUpdateRequest,
        limits: QueryStructuralLimits = .default
    ) throws(SPARQLSemanticValidationError) {
        try validateStructure { () throws(QueryStructuralValidationError) in
            try QueryStructuralValidator.validate(request, limits: limits)
        }
        try validateSemantics(request)
    }

    private static func validateStructure(
        _ operation: () throws(QueryStructuralValidationError) -> Void
    ) throws(SPARQLSemanticValidationError) {
        do {
            try operation()
        } catch {
            throw .structural(error)
        }
    }

    private static func validateSemantics(
        _ request: SPARQLUpdateRequest
    ) throws(SPARQLSemanticValidationError) {
        var insertDataOperationByLabel: [String: Int] = [:]
        var whereClauseByLabel: [String: Int] = [:]
        var whereClauseIdentifier = 0

        for operationIndex in request.indices {
            switch request[operationIndex] {
            case .insertData(let query):
                var labelsInOperation: Set<String> = []
                try validateQuads(
                    query.quads,
                    variableContext: .insertData,
                    onBlankNode: { (label: String) throws(SPARQLSemanticValidationError) -> Void in
                        guard labelsInOperation.insert(label).inserted else {
                            return
                        }
                        if insertDataOperationByLabel[label] != nil {
                            throw .labelCrossesInsertDataOperations(label)
                        }
                        insertDataOperationByLabel[label] = operationIndex
                    }
                )

            case .deleteData(let query):
                try validateQuads(
                    query.quads,
                    variableContext: .deleteData,
                    onBlankNode: { (label: String) throws(SPARQLSemanticValidationError) -> Void in
                        throw .blankNodeNotAllowed(
                            context: .deleteData,
                            label: label
                        )
                    }
                )

            case .modify(let operation):
                if let withGraph = operation.withGraph {
                    try validateIRI(withGraph)
                }
                for reference in operation.using {
                    try validateIRI(reference.iri)
                }
                switch operation.action {
                case .delete(let quads):
                    try validateDeleteTemplate(quads)
                case .insert(let quads):
                    try validateInsertTemplate(quads)
                case .deleteAndInsert(let delete, let insert):
                    try validateDeleteTemplate(delete)
                    try validateInsertTemplate(insert)
                }
                try validateWhereClause(
                    operation.wherePattern,
                    identifier: whereClauseIdentifier,
                    whereClauseByLabel: &whereClauseByLabel
                )
                whereClauseIdentifier += 1

            case .deleteWhere(let query):
                try validateQuads(
                    query.pattern,
                    variableContext: nil,
                    onBlankNode: { (label: String) throws(SPARQLSemanticValidationError) -> Void in
                        throw .blankNodeNotAllowed(
                            context: .deleteWhere,
                            label: label
                        )
                    }
                )
                whereClauseIdentifier += 1

            case .load(let query):
                try validateIRI(query.source)
                if let destination = query.destination {
                    try validateIRI(destination)
                }

            case .clear(let query):
                try validateGraphTarget(query.target)

            case .createGraph(let query):
                try validateIRI(query.graph)

            case .drop(let query):
                try validateGraphTarget(query.target)

            case .graphTransfer(let query):
                try validateGraphTransferEndpoint(query.source)
                try validateGraphTransferEndpoint(query.destination)
            }
        }
    }

    fileprivate static func validateDataset(
        _ dataset: SPARQLDataset
    ) throws(SPARQLSemanticValidationError) {
        guard case .explicit(let defaultGraphs, let namedGraphs) = dataset else {
            return
        }
        for iri in defaultGraphs {
            try validateIRI(iri)
        }
        for iri in namedGraphs {
            try validateIRI(iri)
        }
    }

    private static func validateGraphTarget(
        _ target: SPARQLGraphTarget
    ) throws(SPARQLSemanticValidationError) {
        if case .graph(let iri) = target {
            try validateIRI(iri)
        }
    }

    private static func validateGraphTransferEndpoint(
        _ endpoint: SPARQLGraphTransferEndpoint
    ) throws(SPARQLSemanticValidationError) {
        if case .graph(let iri) = endpoint {
            try validateIRI(iri)
        }
    }

    fileprivate static func validateIRI(
        _ value: String
    ) throws(SPARQLSemanticValidationError) {
        do {
            _ = try RDFIRI(value)
        } catch let error {
            throw .invalidIRI(value, error)
        }
    }

    private static func validateWhereClause(
        _ pattern: GraphPattern,
        identifier: Int,
        whereClauseByLabel: inout [String: Int]
    ) throws(SPARQLSemanticValidationError) {
        var state = QueryScopeState()
        try state.validate(pattern)

        try validateWhereClause(
            state,
            identifier: identifier,
            whereClauseByLabel: &whereClauseByLabel
        )
    }

    private static func validateWhereClause(
        _ state: QueryScopeState,
        identifier: Int,
        whereClauseByLabel: inout [String: Int]
    ) throws(SPARQLSemanticValidationError) {

        for label in state.labels {
            if let existingIdentifier = whereClauseByLabel[label],
               existingIdentifier != identifier {
                throw .labelCrossesWhereClauses(label)
            }
            whereClauseByLabel[label] = identifier
        }
    }

    private static func validateDeleteTemplate(
        _ quads: [Quad]
    ) throws(SPARQLSemanticValidationError) {
        try validateQuads(
            quads,
            variableContext: nil,
            onBlankNode: { (label: String) throws(SPARQLSemanticValidationError) -> Void in
                throw .blankNodeNotAllowed(
                    context: .deleteTemplate,
                    label: label
                )
            }
        )
    }

    private static func validateInsertTemplate(
        _ quads: [Quad]
    ) throws(SPARQLSemanticValidationError) {
        try validateQuads(
            quads,
            variableContext: nil,
            onBlankNode: { _ in }
        )
    }

    private static func validateQuads(
        _ quads: [Quad],
        variableContext: SPARQLSemanticValidationError.GroundDataContext?,
        onBlankNode: (String) throws(SPARQLSemanticValidationError) -> Void
    ) throws(SPARQLSemanticValidationError) {
        for quad in quads {
            if let graph = quad.graph {
                try validateTerm(
                    graph,
                    role: .graphName,
                    variableContext: variableContext,
                    onBlankNode: onBlankNode
                )
            }
            try validateTriple(
                quad.triple,
                variableContext: variableContext,
                onBlankNode: onBlankNode
            )
        }
    }

    private static func validateTriples(
        _ triples: [TriplePattern],
        variableContext: SPARQLSemanticValidationError.GroundDataContext?,
        onBlankNode: (String) throws(SPARQLSemanticValidationError) -> Void
    ) throws(SPARQLSemanticValidationError) {
        for triple in triples {
            try validateTriple(
                triple,
                variableContext: variableContext,
                onBlankNode: onBlankNode
            )
        }
    }

    fileprivate static func validateTriple(
        _ triple: TriplePattern,
        variableContext: SPARQLSemanticValidationError.GroundDataContext?,
        onBlankNode: (String) throws(SPARQLSemanticValidationError) -> Void
    ) throws(SPARQLSemanticValidationError) {
        try validateTerm(
            triple.subject,
            role: .subject,
            variableContext: variableContext,
            onBlankNode: onBlankNode
        )
        try validateTerm(
            triple.predicate,
            role: .predicate,
            variableContext: variableContext,
            onBlankNode: onBlankNode
        )
        try validateTerm(
            triple.object,
            role: .object,
            variableContext: variableContext,
            onBlankNode: onBlankNode
        )
    }

    fileprivate static func validateTerm(
        _ term: SPARQLTerm,
        role: SPARQLSemanticValidationError.TermRole,
        variableContext: SPARQLSemanticValidationError.GroundDataContext?,
        onBlankNode: (String) throws(SPARQLSemanticValidationError) -> Void
    ) throws(SPARQLSemanticValidationError) {
        let kind = termKind(term)
        guard isAllowed(kind, in: role) else {
            throw .invalidTermRole(role: role, kind: kind)
        }

        switch term {
        case .variable(let name):
            try validateVariable(name)
            if let variableContext {
                throw .variableNotAllowed(
                    context: variableContext,
                    name: name
                )
            }
        case .literal(let literal):
            try validateCanonicalTermLiteral(literal)
        case .iri(let value):
            try validateIRI(value)
        case .blankNode(let label):
            try onBlankNode(label)
        case .tripleTerm(let subject, let predicate, let object):
            try validateTerm(
                subject,
                role: .subject,
                variableContext: variableContext,
                onBlankNode: onBlankNode
            )
            try validateTerm(
                predicate,
                role: .predicate,
                variableContext: variableContext,
                onBlankNode: onBlankNode
            )
            try validateTerm(
                object,
                role: .object,
                variableContext: variableContext,
                onBlankNode: onBlankNode
            )
        case .reifiedTriple(let subject, let predicate, let object, let reifier):
            try validateTerm(
                subject,
                role: .subject,
                variableContext: variableContext,
                onBlankNode: onBlankNode
            )
            try validateTerm(
                predicate,
                role: .predicate,
                variableContext: variableContext,
                onBlankNode: onBlankNode
            )
            try validateTerm(
                object,
                role: .object,
                variableContext: variableContext,
                onBlankNode: onBlankNode
            )
            try validateTerm(
                reifier,
                role: .subject,
                variableContext: variableContext,
                onBlankNode: onBlankNode
            )
        }
    }

    fileprivate static func validateVariable(
        _ name: String
    ) throws(SPARQLSemanticValidationError) {
        do {
            _ = try SPARQLVariableName(name)
        } catch {
            throw .invalidVariableName(name, error)
        }
    }

    fileprivate static func literalContainsBlankNode(_ literal: Literal) -> Bool {
        switch literal {
        case .blankNode:
            return true
        case .array(let values):
            for value in values where literalContainsBlankNode(value) {
                return true
            }
            return false
        case .rdfTerm(let term):
            return rdfTermContainsBlankNode(term)
        case .null, .bool, .int, .uint, .decimal, .double, .string, .date,
             .timestamp, .binary, .uuid, .iri, .typedLiteral, .langLiteral,
             .dirLangLiteral:
            return false
        }
    }

    fileprivate static func blankNodeLabel(in literal: Literal) -> String? {
        switch literal {
        case .blankNode(let label):
            return label
        case .array(let values):
            for value in values {
                if let label = blankNodeLabel(in: value) {
                    return label
                }
            }
            return nil
        case .rdfTerm(let term):
            return blankNodeLabel(in: term)
        case .null, .bool, .int, .uint, .decimal, .double, .string, .date,
             .timestamp, .binary, .uuid, .iri, .typedLiteral, .langLiteral,
             .dirLangLiteral:
            return nil
        }
    }

    private static func validateCanonicalTermLiteral(
        _ literal: Literal
    ) throws(SPARQLSemanticValidationError) {
        switch literal {
        case .iri, .blankNode:
            throw .nonCanonicalTermLiteral
        case .rdfTerm(let term):
            guard case .literal = term else {
                throw .nonCanonicalTermLiteral
            }
            return
        case .null, .array:
            throw .invalidTermLiteral
        case .bool, .int, .uint, .decimal, .double, .string, .date,
             .timestamp, .binary, .uuid:
            return
        case .typedLiteral, .langLiteral, .dirLangLiteral:
            try validateExpressionLiteral(literal)
        }
    }

    fileprivate static func validateExpressionLiteral(
        _ literal: Literal
    ) throws(SPARQLSemanticValidationError) {
        switch literal {
        case .iri(let iri):
            try validateIRI(iri)
        case .typedLiteral(_, let datatype):
            do {
                _ = try RDFTypedLiteralDatatype(datatype)
            } catch let error {
                throw .invalidTypedLiteralDatatype(datatype, error)
            }
        case .langLiteral(_, let language):
            do {
                _ = try RDFLanguageTag(language)
            } catch let error {
                throw .invalidLanguageTag(language, error)
            }
        case .dirLangLiteral(_, let language, let direction):
            do {
                _ = try RDFLanguageTag(language)
            } catch let error {
                throw .invalidLanguageTag(language, error)
            }
            guard RDFDirection(rawValue: direction) != nil else {
                throw .invalidBaseDirection(direction)
            }
        case .array(let values):
            for value in values {
                try validateExpressionLiteral(value)
            }
        case .null, .bool, .int, .uint, .decimal, .double, .string, .date,
             .timestamp, .binary, .uuid, .blankNode, .rdfTerm:
            break
        }
    }

    private static func termKind(
        _ term: SPARQLTerm
    ) -> SPARQLSemanticValidationError.TermKind {
        switch term {
        case .variable: return .variable
        case .iri: return .iri
        case .literal: return .literal
        case .blankNode: return .blankNode
        case .tripleTerm: return .tripleTerm
        case .reifiedTriple: return .reifiedTriple
        }
    }

    private static func isAllowed(
        _ kind: SPARQLSemanticValidationError.TermKind,
        in role: SPARQLSemanticValidationError.TermRole
    ) -> Bool {
        switch role {
        case .predicate, .graphName, .describeResource:
            return kind == .variable || kind == .iri
        case .subject:
            return kind != .literal
        case .object:
            return true
        }
    }

    private static func rdfTermContainsBlankNode(
        _ term: RDFTerm
    ) -> Bool {
        switch term {
        case .blankNode:
            return true
        case .tripleTerm(let subject, _, let object):
            return rdfTermContainsBlankNode(subject.term)
                || rdfTermContainsBlankNode(object)
        case .iri, .literal:
            return false
        }
    }

    private static func blankNodeLabel(
        in term: RDFTerm
    ) -> String? {
        switch term {
        case .blankNode(let label):
            return label.rawValue
        case .tripleTerm(let subject, _, let object):
            if let label = blankNodeLabel(in: subject.term) {
                return label
            }
            return blankNodeLabel(in: object)
        case .iri, .literal:
            return nil
        }
    }
}

private enum SPARQLExpressionSemanticContext: Equatable {
    case projection
    case having
    case orderBy
    case filter
    case bind
    case groupBy
    case aggregateOperand
    case other

    var forbiddenAggregateContext: SPARQLSemanticValidationError
        .AggregateContext? {
        switch self {
        case .filter: return .filter
        case .bind: return .bind
        case .groupBy: return .groupBy
        case .aggregateOperand: return .aggregateOperand
        case .projection, .having, .orderBy, .other: return nil
        }
    }
}

private struct QueryScopeState {
    private var nextBasicGraphPatternIdentifier: UInt64 = 0
    private var basicGraphPatternByLabel: [String: UInt64] = [:]
    private var labelsInSourceOrder: [String] = []

    var labels: [String] { labelsInSourceOrder }

    mutating func validate(
        _ query: SelectQuery,
        inputVisibleVariables: Set<String> = []
    ) throws(SPARQLSemanticValidationError) {
        try SPARQLSemanticValidator.validateDataset(query.dataset)
        try validate(
            query.source,
            inputVisibleVariables: inputVisibleVariables
        )

        if let filter = query.filter {
            try validate(filter, context: .filter)
        }
        if let groupBy = query.groupBy {
            for expression in groupBy {
                try validate(expression, context: .groupBy)
            }
        }
        if let having = query.having {
            try validate(having, context: .having)
        }
        if let orderBy = query.orderBy {
            for key in orderBy {
                try validate(key.expression, context: .orderBy)
            }
        }

        let hasGrouping = !(query.groupBy ?? []).isEmpty
            || projectionContainsAggregate(query.projection)
            || query.having.map(containsAggregate) == true
            || (query.orderBy ?? []).contains {
                containsAggregate($0.expression)
            }
        let sourceVisibleVariables = SPARQLVariableScopeAnalyzer
            .scope(of: query.source).visibleVariables
            .union(inputVisibleVariables)
        let groupVisibleVariables = Set(
            (query.groupBy ?? []).compactMap(directVariable)
        )
        try validate(
            query.projection,
            sourceVisibleVariables: sourceVisibleVariables,
            groupVisibleVariables: groupVisibleVariables,
            hasGrouping: hasGrouping
        )

        if let subqueries = query.subqueries {
            for subquery in subqueries {
                try validate(subquery.query)
            }
        }
    }

    mutating func validate(
        _ modifiers: SPARQLSolutionModifiers
    ) throws(SPARQLSemanticValidationError) {
        for expression in modifiers.groupBy {
            try validate(expression, context: .groupBy)
        }
        for expression in modifiers.having {
            try validate(expression, context: .having)
        }
        for key in modifiers.orderBy {
            try validate(key.expression, context: .orderBy)
        }
    }

    mutating func validate(
        _ source: DataSource,
        inputVisibleVariables: Set<String> = []
    ) throws(SPARQLSemanticValidationError) {
        switch source {
        case .subquery(let query, _):
            try validate(query)
        case .join(let join):
            try validate(
                join.left,
                inputVisibleVariables: inputVisibleVariables
            )
            let leftVisible = SPARQLVariableScopeAnalyzer.scope(of: join.left)
                .visibleVariables
            let isLateral = join.type == .lateral
                || join.type == .leftLateral
            try validate(
                join.right,
                inputVisibleVariables: isLateral
                    ? inputVisibleVariables.union(leftVisible)
                    : inputVisibleVariables
            )
            if case .on(let expression) = join.condition {
                try validate(expression, context: .filter)
            }
        case .graphTable(let source):
            if let expression = source.matchPattern.where {
                try validate(expression, context: .filter)
            }
            for path in source.matchPattern.paths {
                try validate(path)
            }
            if let columns = source.columns {
                for column in columns {
                    try validate(column.expression, context: .other)
                }
            }
        case .graphPattern(let pattern):
            try validate(
                pattern,
                inputVisibleVariables: inputVisibleVariables
            )
        case .namedGraph(let name, let pattern):
            try SPARQLSemanticValidator.validateIRI(name)
            try validate(
                pattern,
                inputVisibleVariables: inputVisibleVariables
            )
        case .service(let endpoint, let pattern, _):
            try SPARQLSemanticValidator.validateIRI(endpoint)
            try validate(
                pattern,
                inputVisibleVariables: inputVisibleVariables
            )
        case .union(let sources), .unionAll(let sources),
             .intersect(let sources):
            for source in sources {
                try validate(
                    source,
                    inputVisibleVariables: inputVisibleVariables
                )
            }
        case .except(let lhs, let rhs):
            try validate(
                lhs,
                inputVisibleVariables: inputVisibleVariables
            )
            try validate(
                rhs,
                inputVisibleVariables: inputVisibleVariables
            )
        case .values(let rows, _):
            for row in rows {
                for literal in row {
                    try validateValuesLiteral(literal)
                }
            }
        #if DATABASE_KIT_MULTIPLE_BASES
        case .base(_, let source):
            try validate(
                source,
                inputVisibleVariables: inputVisibleVariables
            )
        #endif
        case .table, .logical:
            break
        }
    }

    mutating func validate(
        _ path: PathPattern
    ) throws(SPARQLSemanticValidationError) {
        for element in path.elements {
            switch element {
            case .node(let node):
                if let properties = node.properties {
                    for property in properties {
                        try validate(property.value, context: .other)
                    }
                }
            case .edge(let edge):
                if let properties = edge.properties {
                    for property in properties {
                        try validate(property.value, context: .other)
                    }
                }
            case .quantified(let path, _):
                try validate(path)
            case .alternation(let paths):
                for path in paths {
                    try validate(path)
                }
            }
        }
    }

    mutating func validate(
        _ pattern: GraphPattern,
        inputVisibleVariables: Set<String> = [],
        subqueryAllowsInput: Bool = false
    ) throws(SPARQLSemanticValidationError) {
        switch pattern {
        case .basic(let basicGraphPattern):
            let identifier = takeBasicGraphPatternIdentifier()
            for element in basicGraphPattern.elements {
                switch element {
                case .triple(let triple):
                    try SPARQLSemanticValidator.validateTriple(
                        triple,
                        variableContext: nil,
                        onBlankNode: {
                            label throws(SPARQLSemanticValidationError) in
                            try register(
                                blankNodeLabel: label,
                                in: identifier
                            )
                        }
                    )
                case .propertyPath(let pathPattern):
                    try validate(
                        pathPattern.subject,
                        role: .subject,
                        in: identifier
                    )
                    try validate(
                        pathPattern.object,
                        role: .object,
                        in: identifier
                    )
                }
            }
        case .join(let lhs, let rhs), .optional(let lhs, let rhs):
            try validate(
                lhs,
                inputVisibleVariables: inputVisibleVariables,
                subqueryAllowsInput: subqueryAllowsInput
            )
            let leftVisible = SPARQLVariableScopeAnalyzer.scope(of: lhs)
                .visibleVariables
            try validate(
                rhs,
                inputVisibleVariables: inputVisibleVariables.union(leftVisible),
                subqueryAllowsInput: subqueryAllowsInput
            )
        case .union(let lhs, let rhs), .minus(let lhs, let rhs):
            try validate(
                lhs,
                inputVisibleVariables: inputVisibleVariables,
                subqueryAllowsInput: subqueryAllowsInput
            )
            try validate(
                rhs,
                inputVisibleVariables: inputVisibleVariables,
                subqueryAllowsInput: subqueryAllowsInput
            )
        case .lateral(let lhs, let rhs):
            try validate(
                lhs,
                inputVisibleVariables: inputVisibleVariables,
                subqueryAllowsInput: subqueryAllowsInput
            )
            let leftVisible = SPARQLVariableScopeAnalyzer.scope(of: lhs)
                .visibleVariables
            try validate(
                rhs,
                inputVisibleVariables: inputVisibleVariables.union(leftVisible),
                subqueryAllowsInput: true
            )
        case .filter(let inner, let expression):
            try validate(
                inner,
                inputVisibleVariables: inputVisibleVariables,
                subqueryAllowsInput: subqueryAllowsInput
            )
            try validate(expression, context: .filter)
        case .bind(let inner, let variable, let expression):
            try validate(
                inner,
                inputVisibleVariables: inputVisibleVariables,
                subqueryAllowsInput: subqueryAllowsInput
            )
            try SPARQLSemanticValidator.validateVariable(variable)
            let visible = SPARQLVariableScopeAnalyzer.scope(of: inner)
                .visibleVariables.union(inputVisibleVariables)
            guard !visible.contains(variable) else {
                throw .variableAlreadyInScope(variable)
            }
            try validate(expression, context: .bind)
        case .graph(let name, let inner):
            try SPARQLSemanticValidator.validateTerm(
                name,
                role: .graphName,
                variableContext: nil,
                onBlankNode: { _ in }
            )
            var visible = inputVisibleVariables
            if case .variable(let variable) = name {
                visible.insert(variable)
            }
            try validate(
                inner,
                inputVisibleVariables: visible,
                subqueryAllowsInput: subqueryAllowsInput
            )
        case .service(let endpoint, let inner, _):
            try SPARQLSemanticValidator.validateIRI(endpoint)
            try validate(
                inner,
                inputVisibleVariables: inputVisibleVariables,
                subqueryAllowsInput: subqueryAllowsInput
            )
        case .subquery(let query):
            try validate(
                query,
                inputVisibleVariables: subqueryAllowsInput
                    ? inputVisibleVariables
                    : []
            )
        case .groupBy(let inner, let expressions, let aggregates):
            try validate(
                inner,
                inputVisibleVariables: inputVisibleVariables,
                subqueryAllowsInput: subqueryAllowsInput
            )
            for expression in expressions {
                try validate(expression, context: .groupBy)
            }
            var targets = Set<String>()
            let groupVariables = Set(expressions.compactMap(directVariable))
            for aggregate in aggregates {
                try SPARQLSemanticValidator.validateVariable(
                    aggregate.variable
                )
                guard targets.insert(aggregate.variable).inserted else {
                    throw .duplicateProjectionTarget(aggregate.variable)
                }
                guard !groupVariables.contains(aggregate.variable) else {
                    throw .variableAlreadyInScope(aggregate.variable)
                }
                try validateAggregate(aggregate.aggregate)
            }
        case .values(let variables, let bindings):
            var seen = Set<String>()
            for variable in variables {
                try SPARQLSemanticValidator.validateVariable(variable)
                guard seen.insert(variable).inserted else {
                    throw .duplicateValuesVariable(variable)
                }
            }
            for (rowIndex, row) in bindings.enumerated() {
                guard row.count == variables.count else {
                    throw .valuesRowWidth(
                        row: rowIndex,
                        expected: variables.count,
                        actual: row.count
                    )
                }
                for literal in row {
                    guard let literal else { continue }
                    try validateValuesLiteral(literal)
                }
            }
        }
    }

    private mutating func takeBasicGraphPatternIdentifier() -> UInt64 {
        let identifier = nextBasicGraphPatternIdentifier
        nextBasicGraphPatternIdentifier &+= 1
        return identifier
    }

    private mutating func validate(
        _ term: SPARQLTerm,
        role: SPARQLSemanticValidationError.TermRole,
        in basicGraphPatternIdentifier: UInt64
    ) throws(SPARQLSemanticValidationError) {
        try SPARQLSemanticValidator.validateTerm(
            term,
            role: role,
            variableContext: nil,
            onBlankNode: { (label: String) throws(SPARQLSemanticValidationError) -> Void in
                try register(
                    blankNodeLabel: label,
                    in: basicGraphPatternIdentifier
                )
            }
        )
    }

    private mutating func register(
        blankNodeLabel label: String,
        in basicGraphPatternIdentifier: UInt64
    ) throws(SPARQLSemanticValidationError) {
        if let existingIdentifier = basicGraphPatternByLabel[label],
           existingIdentifier != basicGraphPatternIdentifier {
            throw .labelCrossesBasicGraphPatterns(label)
        }
        if basicGraphPatternByLabel[label] == nil {
            labelsInSourceOrder.append(label)
        }
        basicGraphPatternByLabel[label] = basicGraphPatternIdentifier
    }

    private mutating func validateAggregate(
        _ aggregate: AggregateFunction
    ) throws(SPARQLSemanticValidationError) {
        switch aggregate {
        case .count(let expression, _):
            if let expression {
                try validate(expression, context: .aggregateOperand)
            }
        case .sum(let expression, _),
             .avg(let expression, _),
             .min(let expression),
             .max(let expression),
             .groupConcat(let expression, _, _),
             .sample(let expression):
            try validate(expression, context: .aggregateOperand)
        case .arrayAgg(let expression, let orderBy, _):
            try validate(expression, context: .aggregateOperand)
            if let orderBy {
                for key in orderBy {
                    try validate(key.expression, context: .aggregateOperand)
                }
            }
        }
    }

    private mutating func validate(
        _ expression: Expression,
        context: SPARQLExpressionSemanticContext
    ) throws(SPARQLSemanticValidationError) {
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
            try validate(lhs, context: context)
            try validate(rhs, context: context)
        case .negate(let value),
             .not(let value),
             .isNull(let value),
             .isNotNull(let value),
             .cast(let value, _),
             .isTriple(let value),
             .subject(let value),
             .predicate(let value),
             .object(let value):
            try validate(value, context: context)
        case .like(let value, _), .regex(let value, _, _):
            try validate(value, context: context)
        case .between(let value, let low, let high):
            try validate(value, context: context)
            try validate(low, context: context)
            try validate(high, context: context)
        case .inList(let value, let values), .notInList(let value, let values):
            try validate(value, context: context)
            for element in values {
                try validate(element, context: context)
            }
        case .inSubquery(let value, let query):
            try validate(value, context: context)
            try validate(query)
        case .aggregate(let aggregate):
            if context == .aggregateOperand {
                throw .nestedAggregate
            }
            if let forbidden = context.forbiddenAggregateContext {
                throw .aggregateNotAllowed(forbidden)
            }
            try validateAggregate(aggregate)
        case .function(let function):
            for argument in function.arguments {
                try validate(argument, context: context)
            }
        case .caseWhen(let cases, let elseResult):
            for pair in cases {
                try validate(pair.condition, context: context)
                try validate(pair.result, context: context)
            }
            if let elseResult {
                try validate(elseResult, context: context)
            }
        case .coalesce(let expressions):
            for expression in expressions {
                try validate(expression, context: context)
            }
        case .triple(let subject, let predicate, let object):
            try validate(subject, context: context)
            try validate(predicate, context: context)
            try validate(object, context: context)
        case .subquery(let query), .exists(let query):
            try validate(query)
        case .literal(let literal):
            if SPARQLSemanticValidator.literalContainsBlankNode(literal) {
                throw .blankNodeNotAllowed(
                    context: .expression,
                    label: SPARQLSemanticValidator
                        .blankNodeLabel(in: literal) ?? ""
                )
            }
            try SPARQLSemanticValidator.validateExpressionLiteral(literal)
        case .column(let column):
            try SPARQLSemanticValidator.validateVariable(column.column)
        case .variable(let variable), .bound(let variable):
            try SPARQLSemanticValidator.validateVariable(variable.name)
        case .parameter:
            break
        }
    }

    private mutating func validate(
        _ projection: Projection,
        sourceVisibleVariables: Set<String>,
        groupVisibleVariables: Set<String>,
        hasGrouping: Bool
    ) throws(SPARQLSemanticValidationError) {
        switch projection {
        case .all:
            break
        case .allFrom:
            break
        case .items(let items), .distinctItems(let items):
            var targets = Set<String>()
            for item in items {
                try validate(item.expression, context: .projection)
                let target: String
                if let alias = item.alias {
                    try SPARQLSemanticValidator.validateVariable(alias)
                    guard !sourceVisibleVariables.contains(alias) else {
                        throw .variableAlreadyInScope(alias)
                    }
                    target = alias
                } else if let variable = directVariable(item.expression) {
                    target = variable
                } else {
                    throw .projectionExpressionRequiresAlias
                }

                guard !targets.contains(target) else {
                    throw .duplicateProjectionTarget(target)
                }

                if hasGrouping {
                    let allowed = groupVisibleVariables.union(targets)
                    if let invalid = variablesOutsideAggregates(
                        in: item.expression
                    ).subtracting(allowed).sorted().first {
                        throw .projectionVariableNotGrouped(invalid)
                    }
                }
                targets.insert(target)
            }
        }
    }

    private mutating func validateValuesLiteral(
        _ literal: Literal
    ) throws(SPARQLSemanticValidationError) {
        if SPARQLSemanticValidator.literalContainsBlankNode(literal) {
            throw .blankNodeNotAllowed(
                context: .values,
                label: SPARQLSemanticValidator.blankNodeLabel(in: literal)
                    ?? ""
            )
        }
        try SPARQLSemanticValidator.validateExpressionLiteral(literal)
    }

    private func projectionContainsAggregate(
        _ projection: Projection
    ) -> Bool {
        switch projection {
        case .items(let items), .distinctItems(let items):
            return items.contains { containsAggregate($0.expression) }
        case .all, .allFrom:
            return false
        }
    }

    private func containsAggregate(_ expression: Expression) -> Bool {
        if case .aggregate = expression { return true }
        return expressionChildren(expression).contains(where: containsAggregate)
    }

    private func variablesOutsideAggregates(
        in expression: Expression
    ) -> Set<String> {
        switch expression {
        case .aggregate:
            return []
        case .variable(let variable):
            return [variable.name]
        case .column(let column):
            return [column.column]
        case .bound(let variable):
            return [variable.name]
        case .subquery, .exists:
            return []
        case .inSubquery(let value, _):
            return variablesOutsideAggregates(in: value)
        default:
            return expressionChildren(expression).reduce(into: Set<String>()) {
                $0.formUnion(variablesOutsideAggregates(in: $1))
            }
        }
    }

    private func expressionChildren(
        _ expression: Expression
    ) -> [Expression] {
        switch expression {
        case .add(let lhs, let rhs), .subtract(let lhs, let rhs),
             .multiply(let lhs, let rhs), .divide(let lhs, let rhs),
             .modulo(let lhs, let rhs), .equal(let lhs, let rhs),
             .notEqual(let lhs, let rhs), .lessThan(let lhs, let rhs),
             .lessThanOrEqual(let lhs, let rhs),
             .greaterThan(let lhs, let rhs),
             .greaterThanOrEqual(let lhs, let rhs), .and(let lhs, let rhs),
             .or(let lhs, let rhs), .nullIf(let lhs, let rhs):
            return [lhs, rhs]
        case .negate(let value), .not(let value), .isNull(let value),
             .isNotNull(let value), .cast(let value, _),
             .isTriple(let value), .subject(let value),
             .predicate(let value), .object(let value), .like(let value, _),
             .regex(let value, _, _):
            return [value]
        case .between(let value, let low, let high):
            return [value, low, high]
        case .inList(let value, let values),
             .notInList(let value, let values):
            return [value] + values
        case .inSubquery(let value, _):
            return [value]
        case .function(let function):
            return function.arguments
        case .caseWhen(let cases, let elseResult):
            var values: [Expression] = []
            values.reserveCapacity(cases.count * 2 + (elseResult == nil ? 0 : 1))
            for pair in cases {
                values.append(pair.condition)
                values.append(pair.result)
            }
            if let elseResult { values.append(elseResult) }
            return values
        case .coalesce(let expressions):
            return expressions
        case .triple(let subject, let predicate, let object):
            return [subject, predicate, object]
        case .aggregate, .subquery, .exists, .literal, .column, .variable,
             .bound, .parameter:
            return []
        }
    }

    private func directVariable(_ expression: Expression) -> String? {
        switch expression {
        case .variable(let variable): return variable.name
        case .column(let column): return column.column
        default: return nil
        }
    }
}
