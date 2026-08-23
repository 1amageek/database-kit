import DatabaseTypes

/// Description of an exact, named index read.
public struct IndexScanSource: Sendable, Equatable, Hashable {
    public let indexName: String
    public let indexType: IndexType
    public let parameters: [String: FieldValue]

    public init(
        indexName: String,
        indexType: IndexType,
        parameters: [String: FieldValue] = [:]
    ) {
        self.indexName = indexName
        self.indexType = indexType
        self.parameters = parameters
    }
}
