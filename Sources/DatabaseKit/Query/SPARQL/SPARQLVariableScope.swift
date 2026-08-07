public struct SPARQLVariableScope: Sendable, Equatable {
    public let visibleVariables: Set<String>
    public let definitelyBoundVariables: Set<String>

    public init(
        visibleVariables: consuming Set<String>,
        definitelyBoundVariables: consuming Set<String>
    ) {
        self.visibleVariables = consume visibleVariables
        self.definitelyBoundVariables = consume definitelyBoundVariables
    }

    public static let empty = SPARQLVariableScope(
        visibleVariables: [],
        definitelyBoundVariables: []
    )
}

public enum SPARQLVariableScopeAnalyzer {
    public static func scope(
        of pattern: GraphPattern
    ) -> SPARQLVariableScope {
        switch pattern {
        case .basic(let basicGraphPattern):
            let variables = basicGraphPattern.elements.reduce(
                into: Set<String>()
            ) { variables, element in
                switch element {
                case .triple(let triple):
                    collectVariables(in: triple, into: &variables)
                case .propertyPath(let pathPattern):
                    collectVariables(
                        in: pathPattern.subject,
                        into: &variables
                    )
                    collectVariables(
                        in: pathPattern.object,
                        into: &variables
                    )
                }
            }
            return SPARQLVariableScope(
                visibleVariables: variables,
                definitelyBoundVariables: variables
            )

        case .join(let left, let right), .lateral(let left, let right):
            return joining(scope(of: left), scope(of: right))

        case .optional(let left, let right):
            let leftScope = scope(of: left)
            let rightScope = scope(of: right)
            return SPARQLVariableScope(
                visibleVariables: leftScope.visibleVariables.union(
                    rightScope.visibleVariables
                ),
                definitelyBoundVariables: leftScope.definitelyBoundVariables
            )

        case .union(let left, let right):
            let leftScope = scope(of: left)
            let rightScope = scope(of: right)
            return SPARQLVariableScope(
                visibleVariables: leftScope.visibleVariables.union(
                    rightScope.visibleVariables
                ),
                definitelyBoundVariables: leftScope.definitelyBoundVariables
                    .intersection(rightScope.definitelyBoundVariables)
            )

        case .filter(let inner, _), .minus(let inner, _):
            return scope(of: inner)

        case .graph(let name, let inner):
            let innerScope = scope(of: inner)
            guard case .variable(let variable) = name else {
                return innerScope
            }
            return SPARQLVariableScope(
                visibleVariables: innerScope.visibleVariables.union([variable]),
                definitelyBoundVariables: innerScope.definitelyBoundVariables
                    .union([variable])
            )

        case .service(_, let inner, let silent):
            let innerScope = scope(of: inner)
            guard silent else { return innerScope }
            return SPARQLVariableScope(
                visibleVariables: innerScope.visibleVariables,
                definitelyBoundVariables: []
            )

        case .bind(let inner, let variable, _):
            let innerScope = scope(of: inner)
            return SPARQLVariableScope(
                visibleVariables: innerScope.visibleVariables.union([variable]),
                definitelyBoundVariables: innerScope.definitelyBoundVariables
            )

        case .values(let variables, let bindings):
            var definitelyBound = Set(variables)
            for row in bindings {
                for column in variables.indices {
                    if column >= row.count || row[column] == nil {
                        definitelyBound.remove(variables[column])
                    }
                }
            }
            return SPARQLVariableScope(
                visibleVariables: Set(variables),
                definitelyBoundVariables: consume definitelyBound
            )

        case .subquery(let query):
            return scope(of: query)

        case .groupBy(_, let expressions, let aggregates):
            var visible = Set<String>()
            visible.reserveCapacity(aggregates.count + expressions.count)
            for aggregate in aggregates {
                visible.insert(aggregate.variable)
            }
            for expression in expressions {
                if let variable = directVariable(in: expression) {
                    visible.insert(variable)
                }
            }
            return SPARQLVariableScope(
                visibleVariables: consume visible,
                definitelyBoundVariables: []
            )

        }
    }

    public static func scope(
        of query: SelectQuery
    ) -> SPARQLVariableScope {
        let sourceScope = scope(of: query.source)
        switch query.projection {
        case .all:
            return sourceScope
        case .allFrom:
            return .empty
        case .items(let items), .distinctItems(let items):
            var visible = Set<String>()
            var definitelyBound = Set<String>()
            for item in items {
                guard let target = projectionTarget(item) else { continue }
                visible.insert(target)
                if let source = directVariable(in: item.expression),
                   sourceScope.definitelyBoundVariables.contains(source) {
                    definitelyBound.insert(target)
                }
            }
            return SPARQLVariableScope(
                visibleVariables: consume visible,
                definitelyBoundVariables: consume definitelyBound
            )
        }
    }

    public static func scope(
        of source: DataSource
    ) -> SPARQLVariableScope {
        switch source {
        case .graphPattern(let pattern), .namedGraph(_, let pattern):
            return scope(of: pattern)
        case .service(_, let pattern, let silent):
            let patternScope = scope(of: pattern)
            guard silent else { return patternScope }
            return SPARQLVariableScope(
                visibleVariables: patternScope.visibleVariables,
                definitelyBoundVariables: []
            )
        case .subquery(let query, _):
            return scope(of: query)
        case .join(let join):
            let left = scope(of: join.left)
            let right = scope(of: join.right)
            switch join.type {
            case .left, .naturalLeft, .leftLateral:
                return SPARQLVariableScope(
                    visibleVariables: left.visibleVariables.union(
                        right.visibleVariables
                    ),
                    definitelyBoundVariables: left.definitelyBoundVariables
                )
            case .right, .naturalRight:
                return SPARQLVariableScope(
                    visibleVariables: left.visibleVariables.union(
                        right.visibleVariables
                    ),
                    definitelyBoundVariables: right.definitelyBoundVariables
                )
            case .full, .naturalFull:
                return SPARQLVariableScope(
                    visibleVariables: left.visibleVariables.union(
                        right.visibleVariables
                    ),
                    definitelyBoundVariables: []
                )
            case .inner, .cross, .natural, .lateral:
                return joining(left, right)
            }
        case .values(let rows, let columnNames):
            guard let columnNames else { return .empty }
            var definitelyBound = Set(columnNames)
            for row in rows where row.count < columnNames.count {
                for index in row.count..<columnNames.count {
                    definitelyBound.remove(columnNames[index])
                }
            }
            return SPARQLVariableScope(
                visibleVariables: Set(columnNames),
                definitelyBoundVariables: consume definitelyBound
            )
        case .union(let sources), .unionAll(let sources):
            return unionScope(sources)
        case .intersect(let sources):
            return sources.reduce(.empty) { joining($0, scope(of: $1)) }
        case .except(let left, _):
            return scope(of: left)
        case .table, .logical, .graphTable:
            return .empty
        }
    }

    private static func joining(
        _ left: SPARQLVariableScope,
        _ right: SPARQLVariableScope
    ) -> SPARQLVariableScope {
        SPARQLVariableScope(
            visibleVariables: left.visibleVariables.union(
                right.visibleVariables
            ),
            definitelyBoundVariables: left.definitelyBoundVariables.union(
                right.definitelyBoundVariables
            )
        )
    }

    private static func unionScope(
        _ sources: [DataSource]
    ) -> SPARQLVariableScope {
        guard let first = sources.first else { return .empty }
        var result = scope(of: first)
        for source in sources.dropFirst() {
            let next = scope(of: source)
            result = SPARQLVariableScope(
                visibleVariables: result.visibleVariables.union(
                    next.visibleVariables
                ),
                definitelyBoundVariables: result.definitelyBoundVariables
                    .intersection(next.definitelyBoundVariables)
            )
        }
        return result
    }

    private static func projectionTarget(
        _ item: ProjectionItem
    ) -> String? {
        item.alias ?? directVariable(in: item.expression)
    }

    private static func directVariable(
        in expression: Expression
    ) -> String? {
        switch expression {
        case .variable(let variable): return variable.name
        case .column(let column): return column.column
        default: return nil
        }
    }

    private static func collectVariables(
        in triple: TriplePattern,
        into variables: inout Set<String>
    ) {
        collectVariables(in: triple.subject, into: &variables)
        collectVariables(in: triple.predicate, into: &variables)
        collectVariables(in: triple.object, into: &variables)
    }

    private static func collectVariables(
        in term: SPARQLTerm,
        into variables: inout Set<String>
    ) {
        switch term {
        case .variable(let variable):
            variables.insert(variable)
        case .tripleTerm(let subject, let predicate, let object):
            collectVariables(in: subject, into: &variables)
            collectVariables(in: predicate, into: &variables)
            collectVariables(in: object, into: &variables)
        case .reifiedTriple(let subject, let predicate, let object, let reifier):
            collectVariables(in: subject, into: &variables)
            collectVariables(in: predicate, into: &variables)
            collectVariables(in: object, into: &variables)
            collectVariables(in: reifier, into: &variables)
        case .iri, .literal, .blankNode:
            break
        }
    }
}
