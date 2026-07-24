import DatabaseTypes
import Core

extension GraphIndexKind {
    public init(
        canonical kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        let metadata = try PropertyGraphIndexMetadata(canonical: kind)
        self.init(
            fromField: metadata.sourceFieldName,
            edgeField: metadata.labelFieldName,
            toField: metadata.targetFieldName,
            graphField: metadata.namespaceFieldName,
            strategy: metadata.declarativeStrategy
        )
    }
}
