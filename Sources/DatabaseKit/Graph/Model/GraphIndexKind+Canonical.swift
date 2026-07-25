import DatabaseTypes

extension GraphIndexKind {
    public init(
        canonical kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        let metadata = try PropertyGraphIndexMetadata(canonical: kind)
        self.init(
            canonicalFields: kind.fields,
            includesEdgeField: !metadata.labelFieldName.isEmpty,
            includesGraphField: metadata.namespaceFieldName != nil,
            strategy: metadata.declarativeStrategy
        )
    }
}
