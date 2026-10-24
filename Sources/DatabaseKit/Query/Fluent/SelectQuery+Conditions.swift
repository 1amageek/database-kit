public extension SelectQuery {
    /// Add WHERE condition: column = literal
    func `where`(_ column: String, equals literal: Literal) -> Self {
        self.where(
            .equal(
                .column(ColumnRef(column: column)),
                .literal(literal)
            )
        )
    }

    /// Add WHERE condition: column = value
    func `where`<Value: QueryLiteralConvertible>(
        _ column: String,
        equals value: Value
    ) throws(QueryLiteralConversionError) -> Self {
        self.where(column, equals: try value.queryLiteral)
    }

    /// Add WHERE condition: column operator literal
    func `where`(
        _ column: String,
        _ op: ComparisonOperator,
        _ literal: Literal
    ) -> Self {
        let colExpr = Expression.column(ColumnRef(column: column))
        let valExpr = Expression.literal(literal)

        let condition: Expression
        switch op {
        case .equal:
            condition = .equal(colExpr, valExpr)
        case .notEqual:
            condition = .notEqual(colExpr, valExpr)
        case .lessThan:
            condition = .lessThan(colExpr, valExpr)
        case .lessThanOrEqual:
            condition = .lessThanOrEqual(colExpr, valExpr)
        case .greaterThan:
            condition = .greaterThan(colExpr, valExpr)
        case .greaterThanOrEqual:
            condition = .greaterThanOrEqual(colExpr, valExpr)
        }

        return self.where(condition)
    }

    /// Add WHERE condition: column operator value
    func `where`<Value: QueryLiteralConvertible>(
        _ column: String,
        _ op: ComparisonOperator,
        _ value: Value
    ) throws(QueryLiteralConversionError) -> Self {
        self.where(column, op, try value.queryLiteral)
    }

    /// Add WHERE column IS NULL
    func whereNull(_ column: String) -> Self {
        self.where(.isNull(.column(ColumnRef(column: column))))
    }

    /// Add WHERE column IS NOT NULL
    func whereNotNull(_ column: String) -> Self {
        self.where(.isNotNull(.column(ColumnRef(column: column))))
    }

    /// Add WHERE column LIKE pattern
    func whereLike(_ column: String, pattern: String) -> Self {
        self.where(
            .patternMatch(subject: .column(ColumnRef(column: column)), pattern: .string(pattern),
                escape: .string("\\"), kind: .like)
        )
    }

    /// Add WHERE column IN (literals...)
    func whereIn(_ column: String, _ literals: [Literal]) -> Self {
        return self.where(.inList(
            .column(ColumnRef(column: column)),
            values: literals.map { .literal($0) }
        ))
    }

    /// Add WHERE column IN (values...)
    func whereIn<Value: QueryLiteralConvertible>(
        _ column: String,
        _ values: [Value]
    ) throws(QueryLiteralConversionError) -> Self {
        var expressions: [Expression] = []
        expressions.reserveCapacity(values.count)
        for value in values {
            expressions.append(.literal(try value.queryLiteral))
        }
        return self.where(
            .inList(
                .column(ColumnRef(column: column)),
                values: expressions
            )
        )
    }

    /// Add WHERE column NOT IN (literals...)
    func whereNotIn(_ column: String, _ literals: [Literal]) -> Self {
        self.where(
            .notInList(
                .column(ColumnRef(column: column)),
                values: literals.map { .literal($0) }
            )
        )
    }

    /// Add WHERE column NOT IN (values...)
    func whereNotIn<Value: QueryLiteralConvertible>(
        _ column: String,
        _ values: [Value]
    ) throws(QueryLiteralConversionError) -> Self {
        var expressions: [Expression] = []
        expressions.reserveCapacity(values.count)
        for value in values {
            expressions.append(.literal(try value.queryLiteral))
        }
        return self.where(
            .notInList(
                .column(ColumnRef(column: column)),
                values: expressions
            )
        )
    }

    /// Add WHERE column BETWEEN low AND high literals
    func whereBetween(
        _ column: String,
        _ low: Literal,
        _ high: Literal
    ) -> Self {
        return self.where(.between(
            .column(ColumnRef(column: column)),
            low: .literal(low),
            high: .literal(high)
        ))
    }

    /// Add WHERE column BETWEEN low AND high values of the same type
    func whereBetween<Value: QueryLiteralConvertible>(
        _ column: String,
        _ low: Value,
        _ high: Value
    ) throws(QueryLiteralConversionError) -> Self {
        self.whereBetween(
            column,
            try low.queryLiteral,
            try high.queryLiteral
        )
    }

}
