/// Immutable eligibility predicate for a canonical Fusion plan.
public struct Filter<Item: Persistable>: FusionQueryInput, Sendable {
    private let expression: Expression

    public init(_ expression: Expression) {
        self.expression = expression
    }

    public init<Value: QueryLiteralConvertible>(
        _ field: Field<Item, Value>,
        equals value: Value
    ) throws {
        self.expression = .equal(
            .col(field.name),
            .literal(try value.queryLiteral)
        )
    }

    public init<Value: QueryLiteralConvertible>(
        _ field: Field<Item, Value?>,
        equals value: Value
    ) throws {
        self.expression = .equal(
            .col(field.name),
            .literal(try value.queryLiteral)
        )
    }

    public init<Value: QueryLiteralConvertible>(
        _ field: Field<Item, Value>,
        in values: [Value]
    ) throws {
        self.expression = .inList(
            .col(field.name),
            values: try values.map { .literal(try $0.queryLiteral) }
        )
    }

    public init<Value: QueryLiteralConvertible & Comparable>(
        _ field: Field<Item, Value>,
        range: ClosedRange<Value>
    ) throws {
        self.expression = .between(
            .col(field.name),
            low: .literal(try range.lowerBound.queryLiteral),
            high: .literal(try range.upperBound.queryLiteral)
        )
    }

    public init<Value: QueryLiteralConvertible & Comparable>(
        _ field: Field<Item, Value>,
        range: Range<Value>
    ) throws {
        self.expression = .and(
            .greaterThanOrEqual(
                .col(field.name),
                .literal(try range.lowerBound.queryLiteral)
            ),
            .lessThan(
                .col(field.name),
                .literal(try range.upperBound.queryLiteral)
            )
        )
    }

    public init<Value: QueryLiteralConvertible & Comparable>(
        _ field: Field<Item, Value>,
        greaterThan value: Value
    ) throws {
        self.expression = .greaterThan(
            .col(field.name),
            .literal(try value.queryLiteral)
        )
    }

    public init<Value: QueryLiteralConvertible & Comparable>(
        _ field: Field<Item, Value>,
        greaterThanOrEqual value: Value
    ) throws {
        self.expression = .greaterThanOrEqual(
            .col(field.name),
            .literal(try value.queryLiteral)
        )
    }

    public init<Value: QueryLiteralConvertible & Comparable>(
        _ field: Field<Item, Value>,
        lessThan value: Value
    ) throws {
        self.expression = .lessThan(
            .col(field.name),
            .literal(try value.queryLiteral)
        )
    }

    public init<Value: QueryLiteralConvertible & Comparable>(
        _ field: Field<Item, Value>,
        lessThanOrEqual value: Value
    ) throws {
        self.expression = .lessThanOrEqual(
            .col(field.name),
            .literal(try value.queryLiteral)
        )
    }

    public var fusionInput: FusionInput {
        FusionInput(operation: .filter(expression))
    }
}
