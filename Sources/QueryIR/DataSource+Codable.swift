/// DataSource+Codable.swift
/// Codable conformance for DataSource and related types using tag-based encoding
///
/// Types with manual Codable:
/// - DataSource (indirect enum)
/// - GraphPattern (indirect enum)
/// - SPARQLTerm (indirect enum)
/// - PropertyPath (indirect enum)
/// - PathElement (enum with recursive types)
/// - JoinCondition (enum with associated values)
/// - PathQuantifier (enum with associated values)
/// - PathMode (enum with associated values)
/// - Projection (enum with associated values)

import Foundation

// MARK: - DataSource + Codable

extension DataSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case tableRef
        case query
        case alias
        case joinClause
        case rows
        case columnNames
        case graphTableSource
        case graphPattern
        case name
        case pattern
        case endpoint
        case silent
        case sources
        case left
        case right
    }

    private enum Tag: String, Codable {
        case table
        case subquery
        case join
        case values
        case graphTable
        case graphPattern
        case namedGraph
        case service
        case union
        case unionAll
        case intersect
        case except
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .table(let ref):
            try container.encode(Tag.table, forKey: .tag)
            try container.encode(ref, forKey: .tableRef)
        case .subquery(let query, let alias):
            try container.encode(Tag.subquery, forKey: .tag)
            try container.encode(query, forKey: .query)
            try container.encode(alias, forKey: .alias)
        case .join(let clause):
            try container.encode(Tag.join, forKey: .tag)
            try container.encode(clause, forKey: .joinClause)
        case .values(let rows, let columnNames):
            try container.encode(Tag.values, forKey: .tag)
            try container.encode(rows, forKey: .rows)
            try container.encodeIfPresent(columnNames, forKey: .columnNames)
        case .graphTable(let source):
            try container.encode(Tag.graphTable, forKey: .tag)
            try container.encode(source, forKey: .graphTableSource)
        case .graphPattern(let pattern):
            try container.encode(Tag.graphPattern, forKey: .tag)
            try container.encode(pattern, forKey: .graphPattern)
        case .namedGraph(let name, let pattern):
            try container.encode(Tag.namedGraph, forKey: .tag)
            try container.encode(name, forKey: .name)
            try container.encode(pattern, forKey: .pattern)
        case .service(let endpoint, let pattern, let silent):
            try container.encode(Tag.service, forKey: .tag)
            try container.encode(endpoint, forKey: .endpoint)
            try container.encode(pattern, forKey: .pattern)
            try container.encode(silent, forKey: .silent)
        case .union(let sources):
            try container.encode(Tag.union, forKey: .tag)
            try container.encode(sources, forKey: .sources)
        case .unionAll(let sources):
            try container.encode(Tag.unionAll, forKey: .tag)
            try container.encode(sources, forKey: .sources)
        case .intersect(let sources):
            try container.encode(Tag.intersect, forKey: .tag)
            try container.encode(sources, forKey: .sources)
        case .except(let left, let right):
            try container.encode(Tag.except, forKey: .tag)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .table:
            self = .table(try container.decode(TableRef.self, forKey: .tableRef))
        case .subquery:
            let query = try container.decode(SelectQuery.self, forKey: .query)
            let alias = try container.decode(String.self, forKey: .alias)
            self = .subquery(query, alias: alias)
        case .join:
            self = .join(try container.decode(JoinClause.self, forKey: .joinClause))
        case .values:
            let rows = try container.decode([[Literal]].self, forKey: .rows)
            let columnNames = try container.decodeIfPresent([String].self, forKey: .columnNames)
            self = .values(rows, columnNames: columnNames)
        case .graphTable:
            self = .graphTable(try container.decode(GraphTableSource.self, forKey: .graphTableSource))
        case .graphPattern:
            self = .graphPattern(try container.decode(GraphPattern.self, forKey: .graphPattern))
        case .namedGraph:
            let name = try container.decode(String.self, forKey: .name)
            let pattern = try container.decode(GraphPattern.self, forKey: .pattern)
            self = .namedGraph(name: name, pattern: pattern)
        case .service:
            let endpoint = try container.decode(String.self, forKey: .endpoint)
            let pattern = try container.decode(GraphPattern.self, forKey: .pattern)
            let silent = try container.decode(Bool.self, forKey: .silent)
            self = .service(endpoint: endpoint, pattern: pattern, silent: silent)
        case .union:
            self = .union(try container.decode([DataSource].self, forKey: .sources))
        case .unionAll:
            self = .unionAll(try container.decode([DataSource].self, forKey: .sources))
        case .intersect:
            self = .intersect(try container.decode([DataSource].self, forKey: .sources))
        case .except:
            let left = try container.decode(DataSource.self, forKey: .left)
            let right = try container.decode(DataSource.self, forKey: .right)
            self = .except(left, right)
        }
    }
}

// MARK: - GraphPattern + Codable

extension GraphPattern: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case triples
        case left
        case right
        case pattern
        case expression
        case name
        case endpoint
        case silent
        case variable
        case variables
        case bindings
        case query
        case expressions
        case aggregates
        case subject
        case path
        case object
    }

    private enum Tag: String, Codable {
        case basic
        case join
        case optional
        case union
        case filter
        case minus
        case graph
        case service
        case bind
        case values
        case subquery
        case groupBy
        case propertyPath
        case lateral
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .basic(let triples):
            try container.encode(Tag.basic, forKey: .tag)
            try container.encode(triples, forKey: .triples)
        case .join(let left, let right):
            try container.encode(Tag.join, forKey: .tag)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
        case .optional(let left, let right):
            try container.encode(Tag.optional, forKey: .tag)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
        case .union(let left, let right):
            try container.encode(Tag.union, forKey: .tag)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
        case .filter(let pattern, let expression):
            try container.encode(Tag.filter, forKey: .tag)
            try container.encode(pattern, forKey: .pattern)
            try container.encode(expression, forKey: .expression)
        case .minus(let left, let right):
            try container.encode(Tag.minus, forKey: .tag)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
        case .graph(let name, let pattern):
            try container.encode(Tag.graph, forKey: .tag)
            try container.encode(name, forKey: .name)
            try container.encode(pattern, forKey: .pattern)
        case .service(let endpoint, let pattern, let silent):
            try container.encode(Tag.service, forKey: .tag)
            try container.encode(endpoint, forKey: .endpoint)
            try container.encode(pattern, forKey: .pattern)
            try container.encode(silent, forKey: .silent)
        case .bind(let pattern, let variable, let expression):
            try container.encode(Tag.bind, forKey: .tag)
            try container.encode(pattern, forKey: .pattern)
            try container.encode(variable, forKey: .variable)
            try container.encode(expression, forKey: .expression)
        case .values(let variables, let bindings):
            try container.encode(Tag.values, forKey: .tag)
            try container.encode(variables, forKey: .variables)
            try container.encode(bindings, forKey: .bindings)
        case .subquery(let query):
            try container.encode(Tag.subquery, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .groupBy(let pattern, let expressions, let aggregates):
            try container.encode(Tag.groupBy, forKey: .tag)
            try container.encode(pattern, forKey: .pattern)
            try container.encode(expressions, forKey: .expressions)
            try container.encode(aggregates, forKey: .aggregates)
        case .propertyPath(let subject, let path, let object):
            try container.encode(Tag.propertyPath, forKey: .tag)
            try container.encode(subject, forKey: .subject)
            try container.encode(path, forKey: .path)
            try container.encode(object, forKey: .object)
        case .lateral(let left, let right):
            try container.encode(Tag.lateral, forKey: .tag)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .basic:
            self = .basic(try container.decode([TriplePattern].self, forKey: .triples))
        case .join:
            let left = try container.decode(GraphPattern.self, forKey: .left)
            let right = try container.decode(GraphPattern.self, forKey: .right)
            self = .join(left, right)
        case .optional:
            let left = try container.decode(GraphPattern.self, forKey: .left)
            let right = try container.decode(GraphPattern.self, forKey: .right)
            self = .optional(left, right)
        case .union:
            let left = try container.decode(GraphPattern.self, forKey: .left)
            let right = try container.decode(GraphPattern.self, forKey: .right)
            self = .union(left, right)
        case .filter:
            let pattern = try container.decode(GraphPattern.self, forKey: .pattern)
            let expression = try container.decode(Expression.self, forKey: .expression)
            self = .filter(pattern, expression)
        case .minus:
            let left = try container.decode(GraphPattern.self, forKey: .left)
            let right = try container.decode(GraphPattern.self, forKey: .right)
            self = .minus(left, right)
        case .graph:
            let name = try container.decode(SPARQLTerm.self, forKey: .name)
            let pattern = try container.decode(GraphPattern.self, forKey: .pattern)
            self = .graph(name: name, pattern: pattern)
        case .service:
            let endpoint = try container.decode(String.self, forKey: .endpoint)
            let pattern = try container.decode(GraphPattern.self, forKey: .pattern)
            let silent = try container.decode(Bool.self, forKey: .silent)
            self = .service(endpoint: endpoint, pattern: pattern, silent: silent)
        case .bind:
            let pattern = try container.decode(GraphPattern.self, forKey: .pattern)
            let variable = try container.decode(String.self, forKey: .variable)
            let expression = try container.decode(Expression.self, forKey: .expression)
            self = .bind(pattern, variable: variable, expression: expression)
        case .values:
            let variables = try container.decode([String].self, forKey: .variables)
            let bindings = try container.decode([[Literal?]].self, forKey: .bindings)
            self = .values(variables: variables, bindings: bindings)
        case .subquery:
            self = .subquery(try container.decode(SelectQuery.self, forKey: .query))
        case .groupBy:
            let pattern = try container.decode(GraphPattern.self, forKey: .pattern)
            let expressions = try container.decode([Expression].self, forKey: .expressions)
            let aggregates = try container.decode([AggregateBinding].self, forKey: .aggregates)
            self = .groupBy(pattern, expressions: expressions, aggregates: aggregates)
        case .propertyPath:
            let subject = try container.decode(SPARQLTerm.self, forKey: .subject)
            let path = try container.decode(PropertyPath.self, forKey: .path)
            let object = try container.decode(SPARQLTerm.self, forKey: .object)
            self = .propertyPath(subject: subject, path: path, object: object)
        case .lateral:
            let left = try container.decode(GraphPattern.self, forKey: .left)
            let right = try container.decode(GraphPattern.self, forKey: .right)
            self = .lateral(left, right)
        }
    }
}

// MARK: - SPARQLTerm + Codable

extension SPARQLTerm: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case value
        case prefix_
        case local
        case literal
        case subject
        case predicate
        case object
        case reifier
    }

    private enum Tag: String, Codable {
        case variable
        case iri
        case prefixedName
        case literal
        case blankNode
        case quotedTriple
        case reifiedTriple
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .variable(let v):
            try container.encode(Tag.variable, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .iri(let v):
            try container.encode(Tag.iri, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .prefixedName(let prefix, let local):
            try container.encode(Tag.prefixedName, forKey: .tag)
            try container.encode(prefix, forKey: .prefix_)
            try container.encode(local, forKey: .local)
        case .literal(let lit):
            try container.encode(Tag.literal, forKey: .tag)
            try container.encode(lit, forKey: .literal)
        case .blankNode(let v):
            try container.encode(Tag.blankNode, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .quotedTriple(let subject, let predicate, let object):
            try container.encode(Tag.quotedTriple, forKey: .tag)
            try container.encode(subject, forKey: .subject)
            try container.encode(predicate, forKey: .predicate)
            try container.encode(object, forKey: .object)
        case .reifiedTriple(let subject, let predicate, let object, let reifier):
            try container.encode(Tag.reifiedTriple, forKey: .tag)
            try container.encode(subject, forKey: .subject)
            try container.encode(predicate, forKey: .predicate)
            try container.encode(object, forKey: .object)
            try container.encode(reifier, forKey: .reifier)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .variable:
            self = .variable(try container.decode(String.self, forKey: .value))
        case .iri:
            self = .iri(try container.decode(String.self, forKey: .value))
        case .prefixedName:
            let prefix = try container.decode(String.self, forKey: .prefix_)
            let local = try container.decode(String.self, forKey: .local)
            self = .prefixedName(prefix: prefix, local: local)
        case .literal:
            self = .literal(try container.decode(Literal.self, forKey: .literal))
        case .blankNode:
            self = .blankNode(try container.decode(String.self, forKey: .value))
        case .quotedTriple:
            let subject = try container.decode(SPARQLTerm.self, forKey: .subject)
            let predicate = try container.decode(SPARQLTerm.self, forKey: .predicate)
            let object = try container.decode(SPARQLTerm.self, forKey: .object)
            self = .quotedTriple(subject: subject, predicate: predicate, object: object)
        case .reifiedTriple:
            let subject = try container.decode(SPARQLTerm.self, forKey: .subject)
            let predicate = try container.decode(SPARQLTerm.self, forKey: .predicate)
            let object = try container.decode(SPARQLTerm.self, forKey: .object)
            let reifier = try container.decode(SPARQLTerm.self, forKey: .reifier)
            self = .reifiedTriple(subject: subject, predicate: predicate, object: object, reifier: reifier)
        }
    }
}

// MARK: - PropertyPath + Codable

extension PropertyPath: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case value
        case path
        case left
        case right
        case iris
        case min
        case max
    }

    private enum Tag: String, Codable {
        case iri
        case inverse
        case sequence
        case alternative
        case zeroOrMore
        case oneOrMore
        case zeroOrOne
        case negation
        case range
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .iri(let v):
            try container.encode(Tag.iri, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .inverse(let path):
            try container.encode(Tag.inverse, forKey: .tag)
            try container.encode(path, forKey: .path)
        case .sequence(let left, let right):
            try container.encode(Tag.sequence, forKey: .tag)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
        case .alternative(let left, let right):
            try container.encode(Tag.alternative, forKey: .tag)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
        case .zeroOrMore(let path):
            try container.encode(Tag.zeroOrMore, forKey: .tag)
            try container.encode(path, forKey: .path)
        case .oneOrMore(let path):
            try container.encode(Tag.oneOrMore, forKey: .tag)
            try container.encode(path, forKey: .path)
        case .zeroOrOne(let path):
            try container.encode(Tag.zeroOrOne, forKey: .tag)
            try container.encode(path, forKey: .path)
        case .negation(let iris):
            try container.encode(Tag.negation, forKey: .tag)
            try container.encode(iris, forKey: .iris)
        case .range(let path, let min, let max):
            try container.encode(Tag.range, forKey: .tag)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(min, forKey: .min)
            try container.encodeIfPresent(max, forKey: .max)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .iri:
            self = .iri(try container.decode(String.self, forKey: .value))
        case .inverse:
            self = .inverse(try container.decode(PropertyPath.self, forKey: .path))
        case .sequence:
            let left = try container.decode(PropertyPath.self, forKey: .left)
            let right = try container.decode(PropertyPath.self, forKey: .right)
            self = .sequence(left, right)
        case .alternative:
            let left = try container.decode(PropertyPath.self, forKey: .left)
            let right = try container.decode(PropertyPath.self, forKey: .right)
            self = .alternative(left, right)
        case .zeroOrMore:
            self = .zeroOrMore(try container.decode(PropertyPath.self, forKey: .path))
        case .oneOrMore:
            self = .oneOrMore(try container.decode(PropertyPath.self, forKey: .path))
        case .zeroOrOne:
            self = .zeroOrOne(try container.decode(PropertyPath.self, forKey: .path))
        case .negation:
            self = .negation(try container.decode([String].self, forKey: .iris))
        case .range:
            let path = try container.decode(PropertyPath.self, forKey: .path)
            let min = try container.decodeIfPresent(Int.self, forKey: .min)
            let max = try container.decodeIfPresent(Int.self, forKey: .max)
            self = .range(path, min: min, max: max)
        }
    }
}

// MARK: - PathElement + Codable

extension PathElement: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case node
        case edge
        case pathPattern
        case quantifier
        case alternatives
    }

    private enum Tag: String, Codable {
        case node
        case edge
        case quantified
        case alternation
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .node(let pattern):
            try container.encode(Tag.node, forKey: .tag)
            try container.encode(pattern, forKey: .node)
        case .edge(let pattern):
            try container.encode(Tag.edge, forKey: .tag)
            try container.encode(pattern, forKey: .edge)
        case .quantified(let pathPattern, let quantifier):
            try container.encode(Tag.quantified, forKey: .tag)
            try container.encode(pathPattern, forKey: .pathPattern)
            try container.encode(quantifier, forKey: .quantifier)
        case .alternation(let alternatives):
            try container.encode(Tag.alternation, forKey: .tag)
            try container.encode(alternatives, forKey: .alternatives)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .node:
            self = .node(try container.decode(NodePattern.self, forKey: .node))
        case .edge:
            self = .edge(try container.decode(EdgePattern.self, forKey: .edge))
        case .quantified:
            let pathPattern = try container.decode(PathPattern.self, forKey: .pathPattern)
            let quantifier = try container.decode(PathQuantifier.self, forKey: .quantifier)
            self = .quantified(pathPattern, quantifier: quantifier)
        case .alternation:
            self = .alternation(try container.decode([PathPattern].self, forKey: .alternatives))
        }
    }
}

// MARK: - JoinCondition + Codable

extension JoinCondition: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case expression
        case columns
    }

    private enum Tag: String, Codable {
        case on
        case using
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .on(let expression):
            try container.encode(Tag.on, forKey: .tag)
            try container.encode(expression, forKey: .expression)
        case .using(let columns):
            try container.encode(Tag.using, forKey: .tag)
            try container.encode(columns, forKey: .columns)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .on:
            self = .on(try container.decode(Expression.self, forKey: .expression))
        case .using:
            self = .using(try container.decode([String].self, forKey: .columns))
        }
    }
}

// MARK: - PathQuantifier + Codable

extension PathQuantifier: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case value
        case min
        case max
    }

    private enum Tag: String, Codable {
        case exactly
        case range
        case zeroOrMore
        case oneOrMore
        case zeroOrOne
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .exactly(let n):
            try container.encode(Tag.exactly, forKey: .tag)
            try container.encode(n, forKey: .value)
        case .range(let min, let max):
            try container.encode(Tag.range, forKey: .tag)
            try container.encodeIfPresent(min, forKey: .min)
            try container.encodeIfPresent(max, forKey: .max)
        case .zeroOrMore:
            try container.encode(Tag.zeroOrMore, forKey: .tag)
        case .oneOrMore:
            try container.encode(Tag.oneOrMore, forKey: .tag)
        case .zeroOrOne:
            try container.encode(Tag.zeroOrOne, forKey: .tag)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .exactly:
            self = .exactly(try container.decode(Int.self, forKey: .value))
        case .range:
            let min = try container.decodeIfPresent(Int.self, forKey: .min)
            let max = try container.decodeIfPresent(Int.self, forKey: .max)
            self = .range(min: min, max: max)
        case .zeroOrMore:
            self = .zeroOrMore
        case .oneOrMore:
            self = .oneOrMore
        case .zeroOrOne:
            self = .zeroOrOne
        }
    }
}

// MARK: - PathMode + Codable

extension PathMode: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case k
    }

    private enum Tag: String, Codable {
        case walk
        case trail
        case acyclic
        case simple
        case anyShortest
        case allShortest
        case shortestK
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .walk:
            try container.encode(Tag.walk, forKey: .tag)
        case .trail:
            try container.encode(Tag.trail, forKey: .tag)
        case .acyclic:
            try container.encode(Tag.acyclic, forKey: .tag)
        case .simple:
            try container.encode(Tag.simple, forKey: .tag)
        case .anyShortest:
            try container.encode(Tag.anyShortest, forKey: .tag)
        case .allShortest:
            try container.encode(Tag.allShortest, forKey: .tag)
        case .shortestK(let k):
            try container.encode(Tag.shortestK, forKey: .tag)
            try container.encode(k, forKey: .k)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .walk:
            self = .walk
        case .trail:
            self = .trail
        case .acyclic:
            self = .acyclic
        case .simple:
            self = .simple
        case .anyShortest:
            self = .anyShortest
        case .allShortest:
            self = .allShortest
        case .shortestK:
            self = .shortestK(try container.decode(Int.self, forKey: .k))
        }
    }
}

// MARK: - Projection + Codable

extension Projection: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case tableName
        case items
    }

    private enum Tag: String, Codable {
        case all
        case allFrom
        case items
        case distinctItems
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all:
            try container.encode(Tag.all, forKey: .tag)
        case .allFrom(let tableName):
            try container.encode(Tag.allFrom, forKey: .tag)
            try container.encode(tableName, forKey: .tableName)
        case .items(let items):
            try container.encode(Tag.items, forKey: .tag)
            try container.encode(items, forKey: .items)
        case .distinctItems(let items):
            try container.encode(Tag.distinctItems, forKey: .tag)
            try container.encode(items, forKey: .items)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .all:
            self = .all
        case .allFrom:
            self = .allFrom(try container.decode(String.self, forKey: .tableName))
        case .items:
            self = .items(try container.decode([ProjectionItem].self, forKey: .items))
        case .distinctItems:
            self = .distinctItems(try container.decode([ProjectionItem].self, forKey: .items))
        }
    }
}
