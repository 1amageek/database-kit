import DatabaseTypes

/// Requested execution resources and read-only transport retrieval preference.
public struct QueryExecutionOptions: Sendable, Hashable {
    public let pageSize: UInt32?
    public let budget: ExecutionBudget
    public let graphPartitions: FieldObject

    public init(pageSize: UInt32? = nil, budget: ExecutionBudget = ExecutionBudget(),
                graphPartitions: FieldObject = FieldObject()) {
        self.pageSize = pageSize
        self.budget = budget
        self.graphPartitions = graphPartitions
    }

    public func validate() throws(QueryExecutionOptionsError) {
        if pageSize == 0 { throw .pageSizeMustBePositive }
    }
}
