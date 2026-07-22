import Core

extension VectorIndexKind {
    public init(
        canonical kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        try kind.validateIdentity(
            identifier: Self.identifier,
            subspaceStructure: Self.subspaceStructure
        )
        try kind.validateMetadataKeys(required: ["dimensions", "metric"])
        try kind.validateFieldCount(1)

        let dimensions = try kind.requireInt("dimensions")
        guard dimensions > 0 else {
            throw .invalidMetadata(identifier: kind.identifier, key: "dimensions")
        }
        let rawMetric = try kind.requireString("metric")
        guard let metric = VectorMetric(rawValue: rawMetric) else {
            throw .invalidMetadata(identifier: kind.identifier, key: "metric")
        }

        self.init(
            fieldNames: kind.fieldNames,
            dimensions: dimensions,
            metric: metric
        )
    }
}
