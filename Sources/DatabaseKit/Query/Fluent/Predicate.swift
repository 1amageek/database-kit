import DatabaseTypes

/// A pure typed predicate; evaluation belongs to the selected execution path.
public indirect enum Predicate<T: Persistable>: Sendable {
    /// Field comparison with a value
    case comparison(FieldComparison<T>)

    /// All predicates must match (AND)
    case and([Predicate<T>])

    /// Any predicate must match (OR)
    case or([Predicate<T>])

    /// Negate the predicate (NOT)
    case not(Predicate<T>)

    /// Always true
    case `true`

    /// Always false
    case `false`

    // MARK: - Logical Operators

    /// Combine predicates with AND
    public static func && (lhs: Predicate<T>, rhs: Predicate<T>) -> Predicate<T> {
        switch (lhs, rhs) {
        case (.and(let left), .and(let right)):
            return .and(left + right)
        case (.and(let left), _):
            return .and(left + [rhs])
        case (_, .and(let right)):
            return .and([lhs] + right)
        default:
            return .and([lhs, rhs])
        }
    }

    /// Combine predicates with OR
    public static func || (lhs: Predicate<T>, rhs: Predicate<T>) -> Predicate<T> {
        switch (lhs, rhs) {
        case (.or(let left), .or(let right)):
            return .or(left + right)
        case (.or(let left), _):
            return .or(left + [rhs])
        case (_, .or(let right)):
            return .or([lhs] + right)
        default:
            return .or([lhs, rhs])
        }
    }

    /// Negate a predicate
    public static prefix func ! (predicate: Predicate<T>) -> Predicate<T> {
        .not(predicate)
    }
}

// MARK: - Field Operators

/// Equal comparison.
public func == <T: Persistable, V: Equatable & FieldValueRepresentable & Sendable>(
    lhs: Field<T, V>,
    rhs: V
) -> Predicate<T> {
    .comparison(FieldComparison(field: lhs, op: .equal, value: rhs))
}

/// Not equal comparison.
public func != <T: Persistable, V: Equatable & FieldValueRepresentable & Sendable>(
    lhs: Field<T, V>,
    rhs: V
) -> Predicate<T> {
    .comparison(FieldComparison(field: lhs, op: .notEqual, value: rhs))
}

/// Less than comparison.
public func < <T: Persistable, V: Comparable & FieldValueRepresentable & Sendable>(
    lhs: Field<T, V>,
    rhs: V
) -> Predicate<T> {
    .comparison(FieldComparison(field: lhs, op: .lessThan, value: rhs))
}

/// Less than or equal comparison.
public func <= <T: Persistable, V: Comparable & FieldValueRepresentable & Sendable>(
    lhs: Field<T, V>,
    rhs: V
) -> Predicate<T> {
    .comparison(FieldComparison(field: lhs, op: .lessThanOrEqual, value: rhs))
}

/// Greater than comparison.
public func > <T: Persistable, V: Comparable & FieldValueRepresentable & Sendable>(
    lhs: Field<T, V>,
    rhs: V
) -> Predicate<T> {
    .comparison(FieldComparison(field: lhs, op: .greaterThan, value: rhs))
}

/// Greater than or equal comparison.
public func >= <T: Persistable, V: Comparable & FieldValueRepresentable & Sendable>(
    lhs: Field<T, V>,
    rhs: V
) -> Predicate<T> {
    .comparison(FieldComparison(field: lhs, op: .greaterThanOrEqual, value: rhs))
}

// MARK: - Optional Field Operators

/// Check if an optional field is nil.
public func == <T: Persistable, V: Sendable>(
    lhs: Field<T, V?>,
    rhs: V?.Type
) -> Predicate<T> where V? == Optional<V> {
    .comparison(FieldComparison(field: lhs, op: .isNil))
}

/// Check if an optional field is not nil.
public func != <T: Persistable, V: Sendable>(
    lhs: Field<T, V?>,
    rhs: V?.Type
) -> Predicate<T> where V? == Optional<V> {
    .comparison(FieldComparison(field: lhs, op: .isNotNil))
}

// MARK: - Typed Predicate Factories

extension Predicate {
    /// Check whether a string field contains a substring.
    public static func contains(
        _ substring: String,
        in field: Field<T, String>
    ) -> Predicate<T> {
        .comparison(
            FieldComparison(field: field, op: .contains, value: substring)
        )
    }

    /// Check whether a string field starts with a prefix.
    public static func hasPrefix(
        _ prefix: String,
        in field: Field<T, String>
    ) -> Predicate<T> {
        .comparison(
            FieldComparison(field: field, op: .hasPrefix, value: prefix)
        )
    }

    /// Check whether a string field ends with a suffix.
    public static func hasSuffix(
        _ suffix: String,
        in field: Field<T, String>
    ) -> Predicate<T> {
        .comparison(
            FieldComparison(field: field, op: .hasSuffix, value: suffix)
        )
    }

    /// Check whether an optional string field contains a substring.
    public static func contains(
        _ substring: String,
        in field: Field<T, String?>
    ) -> Predicate<T> {
        .comparison(
            FieldComparison(
                field: field,
                op: .contains,
                value: .string(substring)
            )
        )
    }

    /// Check whether an optional string field starts with a prefix.
    public static func hasPrefix(
        _ prefix: String,
        in field: Field<T, String?>
    ) -> Predicate<T> {
        .comparison(
            FieldComparison(
                field: field,
                op: .hasPrefix,
                value: .string(prefix)
            )
        )
    }

    /// Check whether an optional string field ends with a suffix.
    public static func hasSuffix(
        _ suffix: String,
        in field: Field<T, String?>
    ) -> Predicate<T> {
        .comparison(
            FieldComparison(
                field: field,
                op: .hasSuffix,
                value: .string(suffix)
            )
        )
    }

    /// Check whether a field matches any value in the supplied collection.
    public static func matchesAny<Value: Equatable & FieldValueRepresentable & Sendable>(
        of values: [Value],
        at field: Field<T, Value>
    ) -> Predicate<T> {
        .comparison(FieldComparison(field: field, values: values))
    }
}

