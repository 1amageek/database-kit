/// Storage-level plan for a wire DatabaseKit query.
public struct DatabaseWireQueryPlan: Sendable, Hashable {
    public let operation: DatabaseWireKeyValueOperation
    public let postFilter: DatabaseWirePredicate?

    public init(
        operation: DatabaseWireKeyValueOperation,
        postFilter: DatabaseWirePredicate?
    ) {
        self.operation = operation
        self.postFilter = postFilter
    }

    public var requiresPostFilter: Bool {
        postFilter != nil
    }
}
