/// Expression.swift
/// Unified expression representation for SQL and SPARQL
///
/// Reference:
/// - ISO/IEC 9075:2023 (SQL expressions)
/// - W3C SPARQL 1.1/1.2 (SPARQL expressions and filters)


// MARK: - Custom Operators for Expression Building

/// Equality expression operator (distinct from Equatable's ==)
infix operator .== : ComparisonPrecedence

/// Inequality expression operator (distinct from Equatable's !=)
infix operator .!= : ComparisonPrecedence

/// Less-than expression operator
infix operator .< : ComparisonPrecedence

/// Less-than-or-equal expression operator
infix operator .<= : ComparisonPrecedence

/// Greater-than expression operator
infix operator .> : ComparisonPrecedence

/// Greater-than-or-equal expression operator
infix operator .>= : ComparisonPrecedence

/// Column reference (SQL)
public struct ColumnRef: Sendable, Equatable, Hashable {
    /// Optional table/alias qualifier
    public let table: String?

    /// Column name
    public let column: String

    public init(table: String? = nil, column: String) {
        self.table = table
        self.column = column
    }

    /// Create an unqualified column reference
    public init(_ column: String) {
        self.table = nil
        self.column = column
    }
}

extension ColumnRef: CustomStringConvertible {
    /// Diagnostic text only; executable SQL is owned by QueryAST's serializer.
    public var description: String {
        let quoted: (String) -> String = { name in
            "\"" + name.map { $0 == "\"" ? "\"\"" : String($0) }.joined() + "\""
        }
        if let table = table {
            return "\(quoted(table)).\(quoted(column))"
        }
        return quoted(column)
    }
}

extension ColumnRef {
    /// Generate unquoted column reference (for display purposes only)
    /// Executable SQL is owned by QueryAST's serializer.
    public var displayName: String {
        if let table = table {
            return "\(table).\(column)"
        }
        return column
    }
}

/// Variable reference (SPARQL)
public struct Variable: Sendable, Equatable, Hashable {
    /// Variable name (without ? prefix)
    public let name: String

    public init(_ name: String) {
        if name.hasPrefix("?") || name.hasPrefix("$") {
            self.name = String(name.dropFirst())
        } else {
            self.name = name
        }
    }
}

extension Variable: CustomStringConvertible {
    public var description: String {
        "?\(name)"
    }
}

/// Aggregate function types
public enum AggregateFunction: Sendable, Equatable, Hashable {
    case count(Expression?, distinct: Bool)
    case sum(Expression, distinct: Bool)
    case avg(Expression, distinct: Bool)
    case min(Expression)
    case max(Expression)
    case groupConcat(Expression, separator: String?, distinct: Bool)
    case sample(Expression)  // SPARQL
    case arrayAgg(Expression, orderBy: [SortKey]?, distinct: Bool)  // SQL

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .count(let expr, let distinct):
            hasher.combine(0)
            hasher.combine(expr)
            hasher.combine(distinct)
        case .sum(let expr, let distinct):
            hasher.combine(1)
            hasher.combine(expr)
            hasher.combine(distinct)
        case .avg(let expr, let distinct):
            hasher.combine(2)
            hasher.combine(expr)
            hasher.combine(distinct)
        case .min(let expr):
            hasher.combine(3)
            hasher.combine(expr)
        case .max(let expr):
            hasher.combine(4)
            hasher.combine(expr)
        case .groupConcat(let expr, let sep, let distinct):
            hasher.combine(5)
            hasher.combine(expr)
            hasher.combine(sep)
            hasher.combine(distinct)
        case .sample(let expr):
            hasher.combine(6)
            hasher.combine(expr)
        case .arrayAgg(let expr, let orderBy, let distinct):
            hasher.combine(7)
            hasher.combine(expr)
            if let orderBy = orderBy {
                for key in orderBy {
                    hasher.combine(key)
                }
            }
            hasher.combine(distinct)
        }
    }
}

/// Function call
public struct FunctionCall: Sendable, Equatable, Hashable {
    /// Exact optional schema identity; quoted syntax is owned by the parser.
    public let schema: String?

    /// Exact unqualified function name.
    public let name: String

    /// Arguments
    public let arguments: [Expression]

    /// DISTINCT modifier (for aggregate-like functions)
    public let distinct: Bool

    /// Explicit SQL VARIADIC expansion of the final array argument.
    public let finalArrayIsVariadic: Bool

    public init(name: String, arguments: [Expression], distinct: Bool = false, schema: String? = nil,
                finalArrayIsVariadic: Bool = false) {
        self.schema = schema
        self.name = name
        self.arguments = arguments
        self.distinct = distinct
        self.finalArrayIsVariadic = finalArrayIsVariadic
    }
}

/// Sort direction
public enum SortDirection: String, Sendable, Equatable, Hashable {
    case ascending
    case descending
}

/// NULL ordering
public enum NullOrdering: String, Sendable, Equatable, Hashable {
    case first
    case last
}

/// Sort key for ORDER BY
public struct SortKey: Sendable, Equatable, Hashable {
    public let expression: Expression
    public let direction: SortDirection
    public let nulls: NullOrdering?

    public init(
        _ expression: Expression,
        direction: SortDirection = .ascending,
        nulls: NullOrdering? = nil
    ) {
        self.expression = expression
        self.direction = direction
        self.nulls = nulls
    }
}

/// CASE WHEN pair (condition → result)
public struct CaseWhenPair: Sendable, Equatable, Hashable {
    public let condition: Expression
    public let result: Expression

    public init(condition: Expression, result: Expression) {
        self.condition = condition
        self.result = result
    }
}

/// Aggregate binding (for SPARQL GROUP BY)
public struct AggregateBinding: Sendable, Equatable, Hashable {
    public let variable: String
    public let aggregate: AggregateFunction

    public init(variable: String, aggregate: AggregateFunction) {
        self.variable = variable
        self.aggregate = aggregate
    }
}

/// Unified expression representation
/// Combines SQL expressions and SPARQL filter expressions
public indirect enum Expression: Sendable, Hashable {
    // MARK: - Literals

    /// Literal value
    case literal(Literal)

    /// A SQL current-value form with optional constant fractional-second precision.
    case currentValue(kind: SQLCurrentValueKind, precision: Int?)

    /// Ordered SQL ARRAY constructor children; execution is owned by the SQL runtime.
    case array([Expression])

    /// Ordered SQL ROW constructor children; this is not a persisted query value.
    case row([Expression])

    /// One contiguous group of SQL array subscripts; later groups remain nested.
    case arrayAccess(Expression, subscripts: [ArraySubscript])

    /// A selected array or JSON collection operator.
    case collectionOperation(CollectionOperator, left: Expression, right: Expression)

    case collate(Expression, collation: SQLCollation)
    case arraySubquery(SelectQuery)
    case wholeRow(String)
    case field(Expression, name: String)
    case fieldExpansion(Expression)

    // MARK: - Identifiers

    /// Column reference: table.column or column
    case column(ColumnRef)

    /// Variable reference: ?var (SPARQL)
    case variable(Variable)

    /// Bound parameter reference.
    case parameter(QueryParameterReference)

    // MARK: - Arithmetic Operations

    /// Addition: a + b
    case add(Expression, Expression)

    /// Subtraction: a - b
    case subtract(Expression, Expression)

    /// Multiplication: a * b
    case multiply(Expression, Expression)

    /// Division: a / b
    case divide(Expression, Expression)

    /// Modulo: a % b
    case modulo(Expression, Expression)

    /// Strict SQL concatenation: text or binary left || right.
    case concatenate(Expression, Expression)

    /// Unary negation: -a
    case negate(Expression)

    // MARK: - Comparison Operations

    /// Equality: a = b
    case equal(Expression, Expression)

    /// Inequality: a != b or a <> b
    case notEqual(Expression, Expression)

    /// Less than: a < b
    case lessThan(Expression, Expression)

    /// Less than or equal: a <= b
    case lessThanOrEqual(Expression, Expression)

    /// Greater than: a > b
    case greaterThan(Expression, Expression)

    /// Greater than or equal: a >= b
    case greaterThanOrEqual(Expression, Expression)

    // MARK: - Logical Operations

    /// Logical AND: a AND b
    case and(Expression, Expression)

    /// Logical OR: a OR b
    case or(Expression, Expression)

    /// Logical NOT: NOT a
    case not(Expression)

    // MARK: - NULL / BOUND Checks

    /// IS NULL check
    case isNull(Expression)

    /// IS NOT NULL check
    case isNotNull(Expression)

    /// SPARQL BOUND(?var) check
    case bound(Variable)

    // MARK: - Pattern Matching

    /// SQL pattern predicate. An absent escape disables escaping.
    case patternMatch(subject: Expression, pattern: Expression, escape: Expression?, kind: PatternMatchKind)

    /// Regex match: REGEX(expr, pattern, flags)
    case regex(Expression, pattern: String, flags: String?)

    // MARK: - Range Operations

    /// BETWEEN: expr BETWEEN low AND high
    case between(Expression, low: Expression, high: Expression)

    /// IN list: expr IN (val1, val2, ...)
    case inList(Expression, values: [Expression])

    /// NOT IN list: expr NOT IN (val1, val2, ...)
    case notInList(Expression, values: [Expression])

    /// IN subquery: expr IN (SELECT ...)
    case inSubquery(Expression, subquery: SelectQuery)

    // MARK: - Aggregate Functions

    /// Aggregate function call
    case aggregate(AggregateFunction)

    // MARK: - Scalar Functions

    /// Function call: function(args...)
    case function(FunctionCall)

    // MARK: - Conditional Expressions

    /// CASE WHEN: CASE WHEN c1 THEN r1 ... ELSE r END
    case caseWhen(operand: Expression? = nil, cases: [CaseWhenPair], elseResult: Expression?)

    /// COALESCE: COALESCE(e1, e2, ...)
    case coalesce([Expression])

    /// NULLIF: NULLIF(e1, e2)
    case nullIf(Expression, Expression)

    /// Eager SQL maximum, ignoring NULL operands.
    case greatest([Expression])

    /// Eager SQL minimum, ignoring NULL operands.
    case least([Expression])

    /// A nonnullable Boolean SQL truth predicate.
    case truthTest(Expression, value: TruthValue, negated: Bool)

    /// A nonnullable Boolean null-safe SQL comparison.
    case isDistinctFrom(Expression, Expression, negated: Bool)

    /// A scalar SQL comparison reduced over an array or one-column subquery.
    case quantifiedComparison(Expression, comparison: ComparisonOperator,
                              quantifier: ComparisonQuantifier, source: QuantifiedComparisonSource)

    // MARK: - Type Conversion

    /// CAST: CAST(expr AS type)
    case cast(Expression, targetType: DataType)

    // MARK: - SPARQL RDF-star Operations

    /// Triple constructor (RDF-star): << s p o >>
    case triple(subject: Expression, predicate: Expression, object: Expression)

    /// IS TRIPLE check
    case isTriple(Expression)

    /// SUBJECT accessor
    case subject(Expression)

    /// PREDICATE accessor
    case predicate(Expression)

    /// OBJECT accessor
    case object(Expression)

    // MARK: - Subqueries

    /// Scalar subquery: (SELECT ...)
    case subquery(SelectQuery)

    /// EXISTS subquery: EXISTS (SELECT ...)
    case exists(SelectQuery)
}

// MARK: - Expression Builder Helpers

extension Expression {
    /// Create a column expression
    public static func col(_ name: String) -> Expression {
        .column(ColumnRef(column: name))
    }

    /// Create a qualified column expression
    public static func col(_ table: String, _ column: String) -> Expression {
        .column(ColumnRef(table: table, column: column))
    }

    /// Create a variable expression
    public static func `var`(_ name: String) -> Expression {
        .variable(Variable(name))
    }

    /// Create a one-based positional parameter expression.
    public static func parameter(position: UInt32) -> Expression {
        .parameter(.position(position))
    }

    /// Create a named parameter expression.
    public static func parameter(name: String) -> Expression {
        .parameter(.name(name))
    }

    /// Create a literal expression
    public static func lit(_ value: Literal) -> Expression {
        .literal(value)
    }

    /// Create a string literal
    public static func string(_ value: String) -> Expression {
        .literal(.string(value))
    }

    /// Create an integer literal
    public static func int(_ value: Int64) -> Expression {
        .literal(.int(value))
    }

    /// Create a double literal
    public static func double(_ value: Double) -> Expression {
        .literal(.double(value))
    }

    /// Create a boolean literal
    public static func bool(_ value: Bool) -> Expression {
        .literal(.bool(value))
    }

    /// Create a NULL literal
    public static var null: Expression {
        .literal(.null)
    }
}

// MARK: - Operator Overloads

extension Expression {
    public static func + (lhs: Expression, rhs: Expression) -> Expression {
        .add(lhs, rhs)
    }

    public static func - (lhs: Expression, rhs: Expression) -> Expression {
        .subtract(lhs, rhs)
    }

    public static func * (lhs: Expression, rhs: Expression) -> Expression {
        .multiply(lhs, rhs)
    }

    public static func / (lhs: Expression, rhs: Expression) -> Expression {
        .divide(lhs, rhs)
    }

    public static func % (lhs: Expression, rhs: Expression) -> Expression {
        .modulo(lhs, rhs)
    }

    public static prefix func - (expr: Expression) -> Expression {
        .negate(expr)
    }

    /// Expression equality (creates an .equal expression)
    /// Use `.==` operator for building SQL/SPARQL equality conditions
    public static func .== (lhs: Expression, rhs: Expression) -> Expression {
        .equal(lhs, rhs)
    }

    /// Expression inequality (creates a .notEqual expression)
    /// Use `.!=` operator for building SQL/SPARQL inequality conditions
    public static func .!= (lhs: Expression, rhs: Expression) -> Expression {
        .notEqual(lhs, rhs)
    }

    public static func .< (lhs: Expression, rhs: Expression) -> Expression {
        .lessThan(lhs, rhs)
    }

    public static func .<= (lhs: Expression, rhs: Expression) -> Expression {
        .lessThanOrEqual(lhs, rhs)
    }

    public static func .> (lhs: Expression, rhs: Expression) -> Expression {
        .greaterThan(lhs, rhs)
    }

    public static func .>= (lhs: Expression, rhs: Expression) -> Expression {
        .greaterThanOrEqual(lhs, rhs)
    }

    public static func && (lhs: Expression, rhs: Expression) -> Expression {
        .and(lhs, rhs)
    }

    public static func || (lhs: Expression, rhs: Expression) -> Expression {
        .or(lhs, rhs)
    }

    public static prefix func ! (expr: Expression) -> Expression {
        .not(expr)
    }
}

// MARK: - Representation Identity

extension Expression: Equatable {
    public static func == (lhs: Expression, rhs: Expression) -> Bool {
        ExpressionIdentity.areEqual(lhs, rhs)
    }
}

extension Expression {
    public func hash(into hasher: inout Hasher) {
        ExpressionIdentity.hash(self, into: &hasher)
    }
}
