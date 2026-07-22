import Core

/// Canonical, non-generic property graph index metadata.
public struct PropertyGraphIndexMetadata: Sendable, Hashable {
    public let strategy: GraphIndexStrategy
    public let declarativeStrategy: PropertyGraphIndexStrategy
    public let sourceFieldName: String
    public let labelFieldName: String
    public let targetFieldName: String
    public let namespaceFieldName: String?

    public init(
        canonical kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        try kind.validateIdentity(
            identifier: "graph",
            subspaceStructure: .hierarchical
        )
        try kind.validateMetadataKeys(
            required: ["strategy", "hasEdgeField", "hasGraphField"]
        )

        let rawStrategy = try kind.requireString("strategy")
        guard let declarativeStrategy = PropertyGraphIndexStrategy(rawValue: rawStrategy) else {
            throw .invalidMetadata(identifier: kind.identifier, key: "strategy")
        }
        let hasEdgeField = try kind.requireBool("hasEdgeField")
        let hasGraphField = try kind.requireBool("hasGraphField")
        let expectedFieldCount = 2 + (hasEdgeField ? 1 : 0) + (hasGraphField ? 1 : 0)
        try kind.validateFieldCount(expectedFieldCount)

        var offset = 0
        self.sourceFieldName = kind.fieldNames[offset]
        offset += 1
        if hasEdgeField {
            self.labelFieldName = kind.fieldNames[offset]
            offset += 1
        } else {
            self.labelFieldName = ""
        }
        self.targetFieldName = kind.fieldNames[offset]
        offset += 1
        self.namespaceFieldName = hasGraphField ? kind.fieldNames[offset] : nil
        self.declarativeStrategy = declarativeStrategy
        self.strategy = declarativeStrategy.storageStrategy
    }
}
