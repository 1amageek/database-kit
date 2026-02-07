/// Expression+Codable.swift
/// Codable conformance for Expression, AggregateFunction, and DataType
///
/// Uses tag-based discriminated encoding for all indirect enums.
/// Each case is identified by a "type" field with a stable string tag.
///
/// Note: Literal+Codable is in Literal+Codable.swift

import Foundation

// MARK: - DataType + Codable

extension DataType: Codable {

    private enum Tag: String, Codable {
        case boolean, smallint, integer, bigint, real, doublePrecision
        case decimal, char, varchar, text
        case date, time, timestamp, interval
        case binary, varbinary, blob
        case json, jsonb, uuid
        case array, custom
    }

    private enum CodingKeys: String, CodingKey {
        case tag, precision, scale, length, withTimeZone, elementType, name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .boolean:
            self = .boolean
        case .smallint:
            self = .smallint
        case .integer:
            self = .integer
        case .bigint:
            self = .bigint
        case .real:
            self = .real
        case .doublePrecision:
            self = .doublePrecision
        case .decimal:
            self = .decimal(
                precision: try container.decodeIfPresent(Int.self, forKey: .precision),
                scale: try container.decodeIfPresent(Int.self, forKey: .scale)
            )
        case .char:
            self = .char(length: try container.decodeIfPresent(Int.self, forKey: .length))
        case .varchar:
            self = .varchar(length: try container.decodeIfPresent(Int.self, forKey: .length))
        case .text:
            self = .text
        case .date:
            self = .date
        case .time:
            self = .time(withTimeZone: try container.decode(Bool.self, forKey: .withTimeZone))
        case .timestamp:
            self = .timestamp(withTimeZone: try container.decode(Bool.self, forKey: .withTimeZone))
        case .interval:
            self = .interval
        case .binary:
            self = .binary(length: try container.decodeIfPresent(Int.self, forKey: .length))
        case .varbinary:
            self = .varbinary(length: try container.decodeIfPresent(Int.self, forKey: .length))
        case .blob:
            self = .blob
        case .json:
            self = .json
        case .jsonb:
            self = .jsonb
        case .uuid:
            self = .uuid
        case .array:
            self = .array(try container.decode(DataType.self, forKey: .elementType))
        case .custom:
            self = .custom(try container.decode(String.self, forKey: .name))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .boolean:
            try container.encode(Tag.boolean, forKey: .tag)
        case .smallint:
            try container.encode(Tag.smallint, forKey: .tag)
        case .integer:
            try container.encode(Tag.integer, forKey: .tag)
        case .bigint:
            try container.encode(Tag.bigint, forKey: .tag)
        case .real:
            try container.encode(Tag.real, forKey: .tag)
        case .doublePrecision:
            try container.encode(Tag.doublePrecision, forKey: .tag)
        case .decimal(let precision, let scale):
            try container.encode(Tag.decimal, forKey: .tag)
            try container.encodeIfPresent(precision, forKey: .precision)
            try container.encodeIfPresent(scale, forKey: .scale)
        case .char(let length):
            try container.encode(Tag.char, forKey: .tag)
            try container.encodeIfPresent(length, forKey: .length)
        case .varchar(let length):
            try container.encode(Tag.varchar, forKey: .tag)
            try container.encodeIfPresent(length, forKey: .length)
        case .text:
            try container.encode(Tag.text, forKey: .tag)
        case .date:
            try container.encode(Tag.date, forKey: .tag)
        case .time(let withTimeZone):
            try container.encode(Tag.time, forKey: .tag)
            try container.encode(withTimeZone, forKey: .withTimeZone)
        case .timestamp(let withTimeZone):
            try container.encode(Tag.timestamp, forKey: .tag)
            try container.encode(withTimeZone, forKey: .withTimeZone)
        case .interval:
            try container.encode(Tag.interval, forKey: .tag)
        case .binary(let length):
            try container.encode(Tag.binary, forKey: .tag)
            try container.encodeIfPresent(length, forKey: .length)
        case .varbinary(let length):
            try container.encode(Tag.varbinary, forKey: .tag)
            try container.encodeIfPresent(length, forKey: .length)
        case .blob:
            try container.encode(Tag.blob, forKey: .tag)
        case .json:
            try container.encode(Tag.json, forKey: .tag)
        case .jsonb:
            try container.encode(Tag.jsonb, forKey: .tag)
        case .uuid:
            try container.encode(Tag.uuid, forKey: .tag)
        case .array(let elementType):
            try container.encode(Tag.array, forKey: .tag)
            try container.encode(elementType, forKey: .elementType)
        case .custom(let name):
            try container.encode(Tag.custom, forKey: .tag)
            try container.encode(name, forKey: .name)
        }
    }
}

// MARK: - AggregateFunction + Codable

extension AggregateFunction: Codable {

    private enum Tag: String, Codable {
        case count, sum, avg, min, max, groupConcat, sample, arrayAgg
    }

    private enum CodingKeys: String, CodingKey {
        case tag, expr, distinct, separator, orderBy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .count:
            self = .count(
                try container.decodeIfPresent(Expression.self, forKey: .expr),
                distinct: try container.decode(Bool.self, forKey: .distinct)
            )
        case .sum:
            self = .sum(
                try container.decode(Expression.self, forKey: .expr),
                distinct: try container.decode(Bool.self, forKey: .distinct)
            )
        case .avg:
            self = .avg(
                try container.decode(Expression.self, forKey: .expr),
                distinct: try container.decode(Bool.self, forKey: .distinct)
            )
        case .min:
            self = .min(try container.decode(Expression.self, forKey: .expr))
        case .max:
            self = .max(try container.decode(Expression.self, forKey: .expr))
        case .groupConcat:
            self = .groupConcat(
                try container.decode(Expression.self, forKey: .expr),
                separator: try container.decodeIfPresent(String.self, forKey: .separator),
                distinct: try container.decode(Bool.self, forKey: .distinct)
            )
        case .sample:
            self = .sample(try container.decode(Expression.self, forKey: .expr))
        case .arrayAgg:
            self = .arrayAgg(
                try container.decode(Expression.self, forKey: .expr),
                orderBy: try container.decodeIfPresent([SortKey].self, forKey: .orderBy),
                distinct: try container.decode(Bool.self, forKey: .distinct)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .count(let expr, let distinct):
            try container.encode(Tag.count, forKey: .tag)
            try container.encodeIfPresent(expr, forKey: .expr)
            try container.encode(distinct, forKey: .distinct)
        case .sum(let expr, let distinct):
            try container.encode(Tag.sum, forKey: .tag)
            try container.encode(expr, forKey: .expr)
            try container.encode(distinct, forKey: .distinct)
        case .avg(let expr, let distinct):
            try container.encode(Tag.avg, forKey: .tag)
            try container.encode(expr, forKey: .expr)
            try container.encode(distinct, forKey: .distinct)
        case .min(let expr):
            try container.encode(Tag.min, forKey: .tag)
            try container.encode(expr, forKey: .expr)
        case .max(let expr):
            try container.encode(Tag.max, forKey: .tag)
            try container.encode(expr, forKey: .expr)
        case .groupConcat(let expr, let separator, let distinct):
            try container.encode(Tag.groupConcat, forKey: .tag)
            try container.encode(expr, forKey: .expr)
            try container.encodeIfPresent(separator, forKey: .separator)
            try container.encode(distinct, forKey: .distinct)
        case .sample(let expr):
            try container.encode(Tag.sample, forKey: .tag)
            try container.encode(expr, forKey: .expr)
        case .arrayAgg(let expr, let orderBy, let distinct):
            try container.encode(Tag.arrayAgg, forKey: .tag)
            try container.encode(expr, forKey: .expr)
            try container.encodeIfPresent(orderBy, forKey: .orderBy)
            try container.encode(distinct, forKey: .distinct)
        }
    }
}

// MARK: - Expression + Codable

extension Expression: Codable {

    private enum Tag: String, Codable {
        case literal, column, variable
        case add, subtract, multiply, divide, modulo, negate
        case equal, notEqual, lessThan, lessThanOrEqual, greaterThan, greaterThanOrEqual
        case and, or, not
        case isNull, isNotNull, bound
        case like, regex
        case between, inList, inSubquery
        case aggregate, function
        case caseWhen, coalesce, nullIf, cast
        case triple, isTriple, subject, predicate, object
        case subquery, exists
    }

    private enum CodingKeys: String, CodingKey {
        case tag
        case lhs, rhs, expr
        case value, variable
        case pattern, flags
        case low, high
        case values
        case aggregateFunction, functionCall
        case cases, elseResult
        case expressions
        case targetType
        case subjectExpr, predicateExpr, objectExpr
        case query
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        // Literals
        case .literal:
            self = .literal(try container.decode(Literal.self, forKey: .value))

        // Identifiers
        case .column:
            self = .column(try container.decode(ColumnRef.self, forKey: .value))
        case .variable:
            self = .variable(try container.decode(Variable.self, forKey: .variable))

        // Binary arithmetic
        case .add:
            self = .add(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )
        case .subtract:
            self = .subtract(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )
        case .multiply:
            self = .multiply(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )
        case .divide:
            self = .divide(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )
        case .modulo:
            self = .modulo(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )

        // Unary arithmetic
        case .negate:
            self = .negate(try container.decode(Expression.self, forKey: .expr))

        // Binary comparison
        case .equal:
            self = .equal(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )
        case .notEqual:
            self = .notEqual(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )
        case .lessThan:
            self = .lessThan(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )
        case .lessThanOrEqual:
            self = .lessThanOrEqual(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )
        case .greaterThan:
            self = .greaterThan(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )
        case .greaterThanOrEqual:
            self = .greaterThanOrEqual(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )

        // Binary logical
        case .and:
            self = .and(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )
        case .or:
            self = .or(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )

        // Unary logical
        case .not:
            self = .not(try container.decode(Expression.self, forKey: .expr))

        // NULL / BOUND checks
        case .isNull:
            self = .isNull(try container.decode(Expression.self, forKey: .expr))
        case .isNotNull:
            self = .isNotNull(try container.decode(Expression.self, forKey: .expr))
        case .bound:
            self = .bound(try container.decode(Variable.self, forKey: .variable))

        // Pattern matching
        case .like:
            self = .like(
                try container.decode(Expression.self, forKey: .expr),
                pattern: try container.decode(String.self, forKey: .pattern)
            )
        case .regex:
            self = .regex(
                try container.decode(Expression.self, forKey: .expr),
                pattern: try container.decode(String.self, forKey: .pattern),
                flags: try container.decodeIfPresent(String.self, forKey: .flags)
            )

        // Range operations
        case .between:
            self = .between(
                try container.decode(Expression.self, forKey: .expr),
                low: try container.decode(Expression.self, forKey: .low),
                high: try container.decode(Expression.self, forKey: .high)
            )
        case .inList:
            self = .inList(
                try container.decode(Expression.self, forKey: .expr),
                values: try container.decode([Expression].self, forKey: .values)
            )
        case .inSubquery:
            self = .inSubquery(
                try container.decode(Expression.self, forKey: .expr),
                subquery: try container.decode(SelectQuery.self, forKey: .query)
            )

        // Aggregate
        case .aggregate:
            self = .aggregate(try container.decode(AggregateFunction.self, forKey: .aggregateFunction))

        // Function
        case .function:
            self = .function(try container.decode(FunctionCall.self, forKey: .functionCall))

        // Conditional
        case .caseWhen:
            self = .caseWhen(
                cases: try container.decode([CaseWhenPair].self, forKey: .cases),
                elseResult: try container.decodeIfPresent(Expression.self, forKey: .elseResult)
            )
        case .coalesce:
            self = .coalesce(try container.decode([Expression].self, forKey: .expressions))
        case .nullIf:
            self = .nullIf(
                try container.decode(Expression.self, forKey: .lhs),
                try container.decode(Expression.self, forKey: .rhs)
            )

        // Type conversion
        case .cast:
            self = .cast(
                try container.decode(Expression.self, forKey: .expr),
                targetType: try container.decode(DataType.self, forKey: .targetType)
            )

        // RDF-star
        case .triple:
            self = .triple(
                subject: try container.decode(Expression.self, forKey: .subjectExpr),
                predicate: try container.decode(Expression.self, forKey: .predicateExpr),
                object: try container.decode(Expression.self, forKey: .objectExpr)
            )
        case .isTriple:
            self = .isTriple(try container.decode(Expression.self, forKey: .expr))
        case .subject:
            self = .subject(try container.decode(Expression.self, forKey: .expr))
        case .predicate:
            self = .predicate(try container.decode(Expression.self, forKey: .expr))
        case .object:
            self = .object(try container.decode(Expression.self, forKey: .expr))

        // Subqueries
        case .subquery:
            self = .subquery(try container.decode(SelectQuery.self, forKey: .query))
        case .exists:
            self = .exists(try container.decode(SelectQuery.self, forKey: .query))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        // Literals
        case .literal(let lit):
            try container.encode(Tag.literal, forKey: .tag)
            try container.encode(lit, forKey: .value)

        // Identifiers
        case .column(let col):
            try container.encode(Tag.column, forKey: .tag)
            try container.encode(col, forKey: .value)
        case .variable(let v):
            try container.encode(Tag.variable, forKey: .tag)
            try container.encode(v, forKey: .variable)

        // Binary arithmetic
        case .add(let lhs, let rhs):
            try container.encode(Tag.add, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .subtract(let lhs, let rhs):
            try container.encode(Tag.subtract, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .multiply(let lhs, let rhs):
            try container.encode(Tag.multiply, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .divide(let lhs, let rhs):
            try container.encode(Tag.divide, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .modulo(let lhs, let rhs):
            try container.encode(Tag.modulo, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)

        // Unary arithmetic
        case .negate(let expr):
            try container.encode(Tag.negate, forKey: .tag)
            try container.encode(expr, forKey: .expr)

        // Binary comparison
        case .equal(let lhs, let rhs):
            try container.encode(Tag.equal, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .notEqual(let lhs, let rhs):
            try container.encode(Tag.notEqual, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .lessThan(let lhs, let rhs):
            try container.encode(Tag.lessThan, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .lessThanOrEqual(let lhs, let rhs):
            try container.encode(Tag.lessThanOrEqual, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .greaterThan(let lhs, let rhs):
            try container.encode(Tag.greaterThan, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .greaterThanOrEqual(let lhs, let rhs):
            try container.encode(Tag.greaterThanOrEqual, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)

        // Binary logical
        case .and(let lhs, let rhs):
            try container.encode(Tag.and, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)
        case .or(let lhs, let rhs):
            try container.encode(Tag.or, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)

        // Unary logical
        case .not(let expr):
            try container.encode(Tag.not, forKey: .tag)
            try container.encode(expr, forKey: .expr)

        // NULL / BOUND checks
        case .isNull(let expr):
            try container.encode(Tag.isNull, forKey: .tag)
            try container.encode(expr, forKey: .expr)
        case .isNotNull(let expr):
            try container.encode(Tag.isNotNull, forKey: .tag)
            try container.encode(expr, forKey: .expr)
        case .bound(let v):
            try container.encode(Tag.bound, forKey: .tag)
            try container.encode(v, forKey: .variable)

        // Pattern matching
        case .like(let expr, let pattern):
            try container.encode(Tag.like, forKey: .tag)
            try container.encode(expr, forKey: .expr)
            try container.encode(pattern, forKey: .pattern)
        case .regex(let expr, let pattern, let flags):
            try container.encode(Tag.regex, forKey: .tag)
            try container.encode(expr, forKey: .expr)
            try container.encode(pattern, forKey: .pattern)
            try container.encodeIfPresent(flags, forKey: .flags)

        // Range operations
        case .between(let expr, let low, let high):
            try container.encode(Tag.between, forKey: .tag)
            try container.encode(expr, forKey: .expr)
            try container.encode(low, forKey: .low)
            try container.encode(high, forKey: .high)
        case .inList(let expr, let values):
            try container.encode(Tag.inList, forKey: .tag)
            try container.encode(expr, forKey: .expr)
            try container.encode(values, forKey: .values)
        case .inSubquery(let expr, let query):
            try container.encode(Tag.inSubquery, forKey: .tag)
            try container.encode(expr, forKey: .expr)
            try container.encode(query, forKey: .query)

        // Aggregate
        case .aggregate(let agg):
            try container.encode(Tag.aggregate, forKey: .tag)
            try container.encode(agg, forKey: .aggregateFunction)

        // Function
        case .function(let call):
            try container.encode(Tag.function, forKey: .tag)
            try container.encode(call, forKey: .functionCall)

        // Conditional
        case .caseWhen(let cases, let elseResult):
            try container.encode(Tag.caseWhen, forKey: .tag)
            try container.encode(cases, forKey: .cases)
            try container.encodeIfPresent(elseResult, forKey: .elseResult)
        case .coalesce(let expressions):
            try container.encode(Tag.coalesce, forKey: .tag)
            try container.encode(expressions, forKey: .expressions)
        case .nullIf(let lhs, let rhs):
            try container.encode(Tag.nullIf, forKey: .tag)
            try container.encode(lhs, forKey: .lhs)
            try container.encode(rhs, forKey: .rhs)

        // Type conversion
        case .cast(let expr, let targetType):
            try container.encode(Tag.cast, forKey: .tag)
            try container.encode(expr, forKey: .expr)
            try container.encode(targetType, forKey: .targetType)

        // RDF-star
        case .triple(let subject, let predicate, let object):
            try container.encode(Tag.triple, forKey: .tag)
            try container.encode(subject, forKey: .subjectExpr)
            try container.encode(predicate, forKey: .predicateExpr)
            try container.encode(object, forKey: .objectExpr)
        case .isTriple(let expr):
            try container.encode(Tag.isTriple, forKey: .tag)
            try container.encode(expr, forKey: .expr)
        case .subject(let expr):
            try container.encode(Tag.subject, forKey: .tag)
            try container.encode(expr, forKey: .expr)
        case .predicate(let expr):
            try container.encode(Tag.predicate, forKey: .tag)
            try container.encode(expr, forKey: .expr)
        case .object(let expr):
            try container.encode(Tag.object, forKey: .tag)
            try container.encode(expr, forKey: .expr)

        // Subqueries
        case .subquery(let query):
            try container.encode(Tag.subquery, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .exists(let query):
            try container.encode(Tag.exists, forKey: .tag)
            try container.encode(query, forKey: .query)
        }
    }
}
