/// A request-local constraint timing transition, validated before execution.
public struct SQLSetConstraints: Sendable, Hashable {
    public let selection: SQLConstraintSelection
    public let deferred: Bool

    public init(selection: SQLConstraintSelection, deferred: Bool) throws(SQLCatalogError) {
        if case .named(let names) = selection {
            guard !names.isEmpty else { throw .invalidConstraintSelection }
            for name in names { try SQLIdentifier.validate(name) }
        }
        self.selection = selection
        self.deferred = deferred
    }
}
