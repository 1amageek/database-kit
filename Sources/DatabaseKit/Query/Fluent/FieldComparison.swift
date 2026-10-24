import DatabaseTypes

/// A compiled field identity, predicate operator and canonical comparison value.
public struct FieldComparison<T: Persistable>: Sendable, Hashable {
    /// The exact compiled schema field selected by this comparison.
    public let field: FieldIdentity

    /// The canonical field name used by planners and
    public var fieldName: String {
        field.name
    }

    /// The comparison operator
    public let op: FieldComparisonOperator

    /// The value to compare against (type-safe)
    public let value: FieldValue

    /// Preserve canonical field identity; execution validates it against the model schema.
    public init(
        field: FieldIdentity,
        op: FieldComparisonOperator,
        value: FieldValue
    ) {
        self.field = field
        self.op = op
        self.value = value
    }

    /// Create a comparison from a compile-time typed field and value.
    public init<V: FieldValueRepresentable>(
        field: Field<T, V>,
        op: FieldComparisonOperator,
        value: V
    ) {
        self.field = field.identity
        self.op = op
        self.value = value.fieldValue
    }

    /// Create a comparison from a typed field and canonical comparison value.
    public init<V>(
        field: Field<T, V>,
        op: FieldComparisonOperator,
        value: FieldValue
    ) {
        self.field = field.identity
        self.op = op
        self.value = value
    }

    /// Create a nil comparison for an optional compiled field.
    public init<V>(
        field: Field<T, V?>,
        op: FieldComparisonOperator
    ) {
        self.field = field.identity
        self.op = op
        self.value = .null
    }

    /// Create an IN comparison from a compiled field.
    public init<V: FieldValueRepresentable>(
        field: Field<T, V>,
        values: [V]
    ) {
        self.field = field.identity
        self.op = .in
        self.value = .array(values.map { $0.fieldValue })
    }

    /// Rebuild a comparison while retaining the exact schema identity.
    public func replacing(
        op: FieldComparisonOperator,
        value: FieldValue? = nil
    ) -> FieldComparison<T> {
        FieldComparison(
            field: field,
            op: op,
            value: value ?? self.value
        )
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(field)
        hasher.combine(op)
        hasher.combine(value)
    }

    public static func == (lhs: FieldComparison<T>, rhs: FieldComparison<T>) -> Bool {
        lhs.field == rhs.field
            && lhs.op == rhs.op
            && lhs.value == rhs.value
    }
}
