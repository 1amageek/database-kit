import Core

extension PermutedIndexKind {
    public init(
        canonical kind: IndexKindMetadata
    ) throws {
        try kind.validateIdentity(
            identifier: Self.identifier,
            subspaceStructure: Self.subspaceStructure
        )
        try kind.validateMetadataKeys(required: ["permutation"])
        try kind.validateFieldCount(minimum: 2)

        let permutation = try Permutation(
            indices: kind.requireIntArray("permutation")
        )
        guard permutation.size == kind.fieldNames.count else {
            throw IndexKindMetadataError.invalidMetadata(
                identifier: kind.identifier,
                key: "permutation"
            )
        }
        self.init(fieldNames: kind.fieldNames, permutation: permutation)
    }
}
