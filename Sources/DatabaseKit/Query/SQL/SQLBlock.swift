/// An immutable, nonempty sequence executed within one request transaction.
public struct SQLBlock: Sendable, Hashable {
    public let steps: [SQLBlockStep]

    public init(
        steps: consuming [SQLBlockStep],
        limits: QueryStructuralLimits = .default
    ) throws(QueryStructuralValidationError) {
        self.steps = consume steps
        try QueryStructuralValidator.validate(self, limits: limits)
    }
}
