/// GraphPattern.swift
/// SPARQL Graph Pattern types
///
/// Reference:
/// - W3C SPARQL 1.1 Query Language (Algebra)
/// - W3C SPARQL 1.2 (Draft)


// Note: Core GraphPattern enum is defined in DataSource.swift
// This file provides additional utilities and extensions.

// MARK: - GraphPattern Builders

extension GraphPattern {
    /// Create a basic graph pattern from triple patterns
    public static func bgp(_ patterns: TriplePattern...) -> GraphPattern {
        .basic(BasicGraphPattern(triples: patterns))
    }

    /// Create a basic graph pattern from an array
    public static func bgp(_ patterns: [TriplePattern]) -> GraphPattern {
        .basic(BasicGraphPattern(triples: patterns))
    }

    /// Create a FILTER pattern
    public static func filtered(_ pattern: GraphPattern, _ condition: Expression) -> GraphPattern {
        .filter(pattern, condition)
    }

    /// Create an OPTIONAL pattern
    public static func leftJoin(_ left: GraphPattern, _ right: GraphPattern) -> GraphPattern {
        .optional(left, right)
    }

    /// Create a UNION of multiple patterns
    public static func unionAll(_ patterns: GraphPattern...) -> GraphPattern {
        guard !patterns.isEmpty else { return .basic([]) }
        return patterns.dropFirst().reduce(patterns[0]) { .union($0, $1) }
    }

    /// Create a UNION of two patterns
    public static func unionTwo(_ left: GraphPattern, _ right: GraphPattern) -> GraphPattern {
        .union(left, right)
    }

    /// Create a MINUS pattern
    public static func difference(_ left: GraphPattern, _ right: GraphPattern) -> GraphPattern {
        .minus(left, right)
    }

    /// Create a BIND pattern
    public static func binding(_ pattern: GraphPattern, _ variable: String, _ expression: Expression) -> GraphPattern {
        .bind(pattern, variable: variable, expression: expression)
    }

    /// Create a VALUES pattern (inline data)
    public static func inlineData(_ variables: [String], _ data: [[Literal?]]) -> GraphPattern {
        .values(variables: variables, bindings: data)
    }

    /// Create a SERVICE pattern (federation)
    public static func federated(_ endpoint: String, _ pattern: GraphPattern, silent: Bool = false) -> GraphPattern {
        .service(endpoint: endpoint, pattern: pattern, silent: silent)
    }

    /// Create a GRAPH pattern (named graph)
    public static func named(_ graphName: SPARQLTerm, _ pattern: GraphPattern) -> GraphPattern {
        .graph(name: graphName, pattern: pattern)
    }

    /// Create a property path pattern
    public static func path(
        subject: SPARQLTerm,
        path: PropertyPath,
        object: SPARQLTerm
    ) -> GraphPattern {
        .propertyPath(subject: subject, path: path, object: object)
    }

    /// Create a one-element basic graph pattern containing a property path.
    public static func propertyPath(
        subject: SPARQLTerm,
        path: PropertyPath,
        object: SPARQLTerm
    ) -> GraphPattern {
        .basic(
            BasicGraphPattern(
                elements: [
                    .propertyPath(
                        SPARQLPropertyPathPattern(
                            subject: subject,
                            path: path,
                            object: object
                        )
                    )
                ]
            )
        )
    }
}

// MARK: - GraphPattern Analysis

extension GraphPattern {
    public var variableScope: SPARQLVariableScope {
        SPARQLVariableScopeAnalyzer.scope(of: self)
    }

    /// Returns the number of triple patterns
    public var tripleCount: Int {
        switch self {
        case .basic(let pattern):
            return pattern.count
        case .join(let left, let right), .optional(let left, let right),
             .union(let left, let right), .minus(let left, let right),
             .lateral(let left, let right):
            return left.tripleCount + right.tripleCount
        case .filter(let pattern, _), .bind(let pattern, _, _),
             .graph(_, let pattern), .service(_, let pattern, _):
            return pattern.tripleCount
        case .values, .subquery:
            return 0
        case .groupBy(let pattern, _, _):
            return pattern.tripleCount
        }
    }

}

// MARK: - SPARQL Serialization

extension GraphPattern {
    /// Generate SPARQL syntax
    public func toSPARQL(prefixes: [String: String] = [:], indent: String = "") throws(QueryLiteralConversionError) -> String {
        switch self {
        case .basic(let pattern):
            return try pattern.elements.map { (element) throws(QueryLiteralConversionError) -> String in
                switch element {
                case .triple(let triple):
                    return try indent + triple.toSPARQL(prefixes: prefixes)
                case .propertyPath(let pathPattern):
                    return "\(indent)\(try pathPattern.subject.toSPARQL(prefixes: prefixes)) \(pathPattern.path.toSPARQL(prefixes: prefixes)) \(try pathPattern.object.toSPARQL(prefixes: prefixes)) ."
                }
            }.joined(separator: "\n")

        case .join(let left, let right):
            return """
            \(try left.toSPARQL(prefixes: prefixes, indent: indent))
            \(try right.toSPARQL(prefixes: prefixes, indent: indent))
            """

        case .optional(let left, let right):
            return """
            \(try left.toSPARQL(prefixes: prefixes, indent: indent))
            \(indent)OPTIONAL {
            \(try right.toSPARQL(prefixes: prefixes, indent: indent + "  "))
            \(indent)}
            """

        case .union(let left, let right):
            return """
            \(indent){
            \(try left.toSPARQL(prefixes: prefixes, indent: indent + "  "))
            \(indent)}
            \(indent)UNION
            \(indent){
            \(try right.toSPARQL(prefixes: prefixes, indent: indent + "  "))
            \(indent)}
            """

        case .filter(let pattern, let condition):
            return """
            \(try pattern.toSPARQL(prefixes: prefixes, indent: indent))
            \(indent)FILTER(\(try condition.toSPARQL()))
            """

        case .minus(let left, let right):
            return """
            \(try left.toSPARQL(prefixes: prefixes, indent: indent))
            \(indent)MINUS {
            \(try right.toSPARQL(prefixes: prefixes, indent: indent + "  "))
            \(indent)}
            """

        case .graph(let name, let pattern):
            return """
            \(indent)GRAPH \(try name.toSPARQL(prefixes: prefixes)) {
            \(try pattern.toSPARQL(prefixes: prefixes, indent: indent + "  "))
            \(indent)}
            """

        case .service(let endpoint, let pattern, let silent):
            let silentStr = silent ? "SILENT " : ""
            return """
            \(indent)SERVICE \(silentStr)\(SPARQLEscape.iri(endpoint)) {
            \(try pattern.toSPARQL(prefixes: prefixes, indent: indent + "  "))
            \(indent)}
            """

        case .bind(let pattern, let variable, let expression):
            return """
            \(try pattern.toSPARQL(prefixes: prefixes, indent: indent))
            \(indent)BIND(\(try expression.toSPARQL()) AS ?\(variable))
            """

        case .values(let variables, let bindings):
            let varsStr = variables.map { "?\($0)" }.joined(separator: " ")
            var rows: [String] = []
            for binding in bindings {
                let vals = try binding.map { (value) throws(QueryLiteralConversionError) -> String in try value?.toSPARQL() ?? "UNDEF" }.joined(separator: " ")
                rows.append("(\(vals))")
            }
            return """
            \(indent)VALUES (\(varsStr)) {
            \(rows.map { indent + "  " + $0 }.joined(separator: "\n"))
            \(indent)}
            """

        case .subquery(let query):
            return """
            \(indent){
            \(indent)  \(try query.toSPARQL(prefixes: prefixes))
            \(indent)}
            """

        case .groupBy(let pattern, let expressions, _):
            let groupByStr = expressions.isEmpty ? "" :
                try "\n\(indent)GROUP BY " + expressions.map { (value) throws(QueryLiteralConversionError) -> String in try value.toSPARQL() }.joined(separator: " ")
            return """
            \(try pattern.toSPARQL(prefixes: prefixes, indent: indent))\(groupByStr)
            """

        case .lateral(let left, let right):
            return """
            \(try left.toSPARQL(prefixes: prefixes, indent: indent))
            \(indent)LATERAL {
            \(try right.toSPARQL(prefixes: prefixes, indent: indent + "  "))
            \(indent)}
            """
        }
    }
}

extension Expression {
    /// Generate SPARQL expression syntax
    /// Independent implementation for proper SPARQL semantics
    public func toSPARQL(prefixes: [String: String] = [:]) throws(QueryLiteralConversionError) -> String {
        switch self {
        // FIXME(INCOMPLETE_IMPLEMENTATION): SPARQL admission rejects SQL-only constructors here.
        // S07/S08 must supply SQL execution; RDF term semantics cannot implement these forms.
        case .array, .row:
            throw .unsupportedSPARQLLiteral
        case .literal(let lit):
            return try lit.toSPARQL()

        case .variable(let v):
            return "?\(v.name)"

        case .parameter(let reference):
            switch reference {
            case .position(let position):
                return "$\(position)"
            case .name(let name):
                return ":\(name)"
            }

        case .column(let col):
            // In SPARQL context, columns are treated as variables
            return "?\(col.column)"

        // Comparison operations
        case .equal(let l, let r):
            return "(\(try l.toSPARQL(prefixes: prefixes)) = \(try r.toSPARQL(prefixes: prefixes)))"

        case .notEqual(let l, let r):
            return "(\(try l.toSPARQL(prefixes: prefixes)) != \(try r.toSPARQL(prefixes: prefixes)))"

        case .lessThan(let l, let r):
            return "(\(try l.toSPARQL(prefixes: prefixes)) < \(try r.toSPARQL(prefixes: prefixes)))"

        case .lessThanOrEqual(let l, let r):
            return "(\(try l.toSPARQL(prefixes: prefixes)) <= \(try r.toSPARQL(prefixes: prefixes)))"

        case .greaterThan(let l, let r):
            return "(\(try l.toSPARQL(prefixes: prefixes)) > \(try r.toSPARQL(prefixes: prefixes)))"

        case .greaterThanOrEqual(let l, let r):
            return "(\(try l.toSPARQL(prefixes: prefixes)) >= \(try r.toSPARQL(prefixes: prefixes)))"

        // Logical operations
        case .and(let l, let r):
            return "(\(try l.toSPARQL(prefixes: prefixes)) && \(try r.toSPARQL(prefixes: prefixes)))"

        case .or(let l, let r):
            return "(\(try l.toSPARQL(prefixes: prefixes)) || \(try r.toSPARQL(prefixes: prefixes)))"

        case .not(let e):
            return "!(\(try e.toSPARQL(prefixes: prefixes)))"

        // Arithmetic operations
        case .add(let l, let r):
            return "(\(try l.toSPARQL(prefixes: prefixes)) + \(try r.toSPARQL(prefixes: prefixes)))"

        case .subtract(let l, let r):
            return "(\(try l.toSPARQL(prefixes: prefixes)) - \(try r.toSPARQL(prefixes: prefixes)))"

        case .multiply(let l, let r):
            return "(\(try l.toSPARQL(prefixes: prefixes)) * \(try r.toSPARQL(prefixes: prefixes)))"

        case .divide(let l, let r):
            return "(\(try l.toSPARQL(prefixes: prefixes)) / \(try r.toSPARQL(prefixes: prefixes)))"

        case .modulo(let l, let r):
            // SPARQL doesn't have modulo, use floor division
            return "((\(try l.toSPARQL(prefixes: prefixes))) - (FLOOR((\(try l.toSPARQL(prefixes: prefixes))) / (\(try r.toSPARQL(prefixes: prefixes)))) * (\(try r.toSPARQL(prefixes: prefixes)))))"

        case .negate(let e):
            return "-(\(try e.toSPARQL(prefixes: prefixes)))"

        // NULL / BOUND checks
        case .isNull(let e):
            return "(!BOUND(\(try e.toSPARQL(prefixes: prefixes))))"

        case .isNotNull(let e):
            return "BOUND(\(try e.toSPARQL(prefixes: prefixes)))"

        case .bound(let v):
            return "BOUND(?\(v.name))"

        // Pattern matching
        case .like(let e, let pattern):
            // Convert SQL LIKE to REGEX
            let regexPattern = Self.regexPattern(fromSQLLike: pattern)
            return "REGEX(\(try e.toSPARQL(prefixes: prefixes)), \"^\(regexPattern)$\", \"i\")"

        case .regex(let text, let pattern, let flags):
            if let f = flags {
                return "REGEX(\(try text.toSPARQL(prefixes: prefixes)), \"\(pattern)\", \"\(f)\")"
            }
            return "REGEX(\(try text.toSPARQL(prefixes: prefixes)), \"\(pattern)\")"

        // Range operations
        case .between(let e, let low, let high):
            return "((\(try e.toSPARQL(prefixes: prefixes)) >= \(try low.toSPARQL(prefixes: prefixes))) && (\(try e.toSPARQL(prefixes: prefixes)) <= \(try high.toSPARQL(prefixes: prefixes))))"

        case .inList(let e, let values):
            let vals = try values.map { (value) throws(QueryLiteralConversionError) -> String in try value.toSPARQL(prefixes: prefixes) }.joined(separator: ", ")
            return "(\(try e.toSPARQL(prefixes: prefixes)) IN (\(vals)))"

        case .notInList(let e, let values):
            let vals = try values.map { (value) throws(QueryLiteralConversionError) -> String in try value.toSPARQL(prefixes: prefixes) }.joined(separator: ", ")
            return "(\(try e.toSPARQL(prefixes: prefixes)) NOT IN (\(vals)))"

        case .inSubquery(let e, let subquery):
            return "(\(try e.toSPARQL(prefixes: prefixes)) IN { \(try subquery.toSPARQL(prefixes: prefixes)) })"

        // Aggregates
        case .aggregate(let agg):
            return try agg.toSPARQL(prefixes: prefixes)

        // Functions
        case .function(let call):
            let args = try call.arguments.map { (value) throws(QueryLiteralConversionError) -> String in try value.toSPARQL(prefixes: prefixes) }.joined(separator: ", ")
            return "\(call.name.uppercased())(\(args))"

        // Conditional
        case .caseWhen(let cases, let elseResult):
            // SPARQL uses IF for conditionals
            if cases.count == 1, let first = cases.first {
                let elseStr = try elseResult?.toSPARQL(prefixes: prefixes) ?? "UNDEF"
                return "IF(\(try first.condition.toSPARQL(prefixes: prefixes)), \(try first.result.toSPARQL(prefixes: prefixes)), \(elseStr))"
            }
            // Nested IF for multiple cases
            var result = try elseResult?.toSPARQL(prefixes: prefixes) ?? "UNDEF"
            for pair in cases.reversed() {
                result = "IF(\(try pair.condition.toSPARQL(prefixes: prefixes)), \(try pair.result.toSPARQL(prefixes: prefixes)), \(result))"
            }
            return result

        case .coalesce(let exprs):
            let args = try exprs.map { (value) throws(QueryLiteralConversionError) -> String in try value.toSPARQL(prefixes: prefixes) }.joined(separator: ", ")
            return "COALESCE(\(args))"

        case .nullIf(let e1, let e2):
            return "IF(\(try e1.toSPARQL(prefixes: prefixes)) = \(try e2.toSPARQL(prefixes: prefixes)), UNDEF, \(try e1.toSPARQL(prefixes: prefixes)))"

        // Type conversion
        case .cast(let e, let targetType):
            var scalarType = targetType
            while case .array(let element) = scalarType { scalarType = element }
            // FIXME(INCOMPLETE_IMPLEMENTATION): RDF generation cannot represent SQL temporal precision.
            // S06 must supply SQL conversion without dropping nested modifiers at this RDF boundary.
            switch scalarType {
            case .time(_, .some), .timestamp(_, .some): throw .unsupportedSPARQLLiteral
            default: break
            }
            return "\(targetType.sparqlFunction)(\(try e.toSPARQL(prefixes: prefixes)))"

        // RDF-star operations
        case .triple(let subject, let predicate, let object):
            return "<< \(try subject.toSPARQL(prefixes: prefixes)) \(try predicate.toSPARQL(prefixes: prefixes)) \(try object.toSPARQL(prefixes: prefixes)) >>"

        case .isTriple(let e):
            return "isTRIPLE(\(try e.toSPARQL(prefixes: prefixes)))"

        case .subject(let e):
            return "SUBJECT(\(try e.toSPARQL(prefixes: prefixes)))"

        case .predicate(let e):
            return "PREDICATE(\(try e.toSPARQL(prefixes: prefixes)))"

        case .object(let e):
            return "OBJECT(\(try e.toSPARQL(prefixes: prefixes)))"

        // Subqueries
        case .subquery(let query):
            return "{ \(try query.toSPARQL(prefixes: prefixes)) }"

        case .exists(let query):
            return "EXISTS { \(try query.toSPARQL(prefixes: prefixes)) }"
        }
    }

    private static func regexPattern(fromSQLLike pattern: String) -> String {
        var result = ""
        result.reserveCapacity(pattern.count)
        for character in pattern {
            switch character {
            case "%": result += ".*"
            case "_": result += "."
            default: result.append(character)
            }
        }
        return result
    }
}

extension AggregateFunction {
    /// Generate SPARQL aggregate syntax
    public func toSPARQL(prefixes: [String: String] = [:]) throws(QueryLiteralConversionError) -> String {
        switch self {
        case .count(let expr, let distinct):
            let distinctStr = distinct ? "DISTINCT " : ""
            if let e = expr {
                return "COUNT(\(distinctStr)\(try e.toSPARQL(prefixes: prefixes)))"
            }
            return "COUNT(\(distinctStr)*)"

        case .sum(let expr, let distinct):
            let distinctStr = distinct ? "DISTINCT " : ""
            return "SUM(\(distinctStr)\(try expr.toSPARQL(prefixes: prefixes)))"

        case .avg(let expr, let distinct):
            let distinctStr = distinct ? "DISTINCT " : ""
            return "AVG(\(distinctStr)\(try expr.toSPARQL(prefixes: prefixes)))"

        case .min(let expr):
            return "MIN(\(try expr.toSPARQL(prefixes: prefixes)))"

        case .max(let expr):
            return "MAX(\(try expr.toSPARQL(prefixes: prefixes)))"

        case .groupConcat(let expr, let separator, let distinct):
            let distinctStr = distinct ? "DISTINCT " : ""
            if let sep = separator {
                return "GROUP_CONCAT(\(distinctStr)\(try expr.toSPARQL(prefixes: prefixes)); SEPARATOR=\"\(sep)\")"
            }
            return "GROUP_CONCAT(\(distinctStr)\(try expr.toSPARQL(prefixes: prefixes)))"

        case .sample(let expr):
            return "SAMPLE(\(try expr.toSPARQL(prefixes: prefixes)))"

        case .arrayAgg(let expr, _, let distinct):
            // SPARQL doesn't have ARRAY_AGG, use GROUP_CONCAT as approximation
            let distinctStr = distinct ? "DISTINCT " : ""
            return "GROUP_CONCAT(\(distinctStr)\(try expr.toSPARQL(prefixes: prefixes)))"
        }
    }
}

extension DataType {
    /// Get the SPARQL function name for this data type
    public var sparqlFunction: String {
        switch self {
        case .boolean:
            return "xsd:boolean"
        case .smallint, .integer, .bigint:
            return "xsd:integer"
        case .real, .doublePrecision:
            return "xsd:double"
        case .decimal:
            return "xsd:decimal"
        case .char, .varchar, .text:
            return "xsd:string"
        case .date:
            return "xsd:date"
        case .time:
            return "xsd:time"
        case .timestamp:
            return "xsd:dateTime"
        case .binary, .varbinary, .blob:
            return "xsd:base64Binary"
        case .uuid:
            return "xsd:string"
        case .json, .jsonb:
            return "xsd:string"
        case .interval:
            return "xsd:duration"
        case .array:
            return "xsd:string"
        case .custom(let name):
            return name
        }
    }
}

extension SelectQuery {
    /// Generate SPARQL SELECT query syntax
    public func toSPARQL(prefixes: [String: String] = [:]) throws(QueryLiteralConversionError) -> String {
        var result = ""

        // Prefixes
        for prefix in prefixes.keys.sorted() {
            guard SPARQLEscape.prefixOrNil(prefix) != nil,
                  let iri = prefixes[prefix] else {
                continue
            }
            result += "PREFIX \(prefix): \(SPARQLEscape.iri(iri))\n"
        }

        // SELECT clause
        result += "SELECT "
        if distinct { result += "DISTINCT " }
        if reduced { result += "REDUCED " }

        switch projection {
        case .all:
            result += "*"
        case .allFrom(let table):
            result += "\(table).*"
        case .items(let items), .distinctItems(let items):
            result += try items.map { (item) throws(QueryLiteralConversionError) -> String in
                var s = try item.expression.toSPARQL()
                if let alias = item.alias {
                    s = "(\(s) AS ?\(alias))"
                }
                return s
            }.joined(separator: " ")
        }

        result += "\n"

        // WHERE clause
        if case .graphPattern(let pattern) = source {
            result += "WHERE {\n"
            result += try pattern.toSPARQL(prefixes: prefixes, indent: "  ")
            result += "\n}\n"
        }

        // GROUP BY
        if let groupBy = groupBy, !groupBy.isEmpty {
            result += try "GROUP BY " + groupBy.map { (value) throws(QueryLiteralConversionError) -> String in try value.toSPARQL() }.joined(separator: " ") + "\n"
        }

        // HAVING
        if let having = having {
            result += "HAVING(\(try having.toSPARQL()))\n"
        }

        // ORDER BY
        if let orderBy = orderBy, !orderBy.isEmpty {
            result += try "ORDER BY " + orderBy.map { (key) throws(QueryLiteralConversionError) -> String in
                let dir = key.direction == .descending ? "DESC" : "ASC"
                return "\(dir)(\(try key.expression.toSPARQL()))"
            }.joined(separator: " ") + "\n"
        }

        // LIMIT
        if let limit = limit {
            result += "LIMIT \(limit)\n"
        }

        // OFFSET
        if let offset = offset {
            result += "OFFSET \(offset)\n"
        }

        return result
    }
}
