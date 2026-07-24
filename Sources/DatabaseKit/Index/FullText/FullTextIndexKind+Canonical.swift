
extension FullTextIndexKind {
    public init(
        canonical kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        try kind.validateIdentity(
            identifier: Self.identifier,
            subspaceStructure: Self.subspaceStructure
        )
        try kind.validateMetadataKeys(
            required: ["tokenizer", "storePositions", "ngramSize", "minTermLength"]
        )
        try kind.validateFieldCount(minimum: 1)

        let rawTokenizer = try kind.requireString("tokenizer")
        guard let tokenizer = TokenizationStrategy(rawValue: rawTokenizer) else {
            throw .invalidMetadata(identifier: kind.identifier, key: "tokenizer")
        }
        let ngramSize = try kind.requireInt("ngramSize")
        guard ngramSize > 0 else {
            throw .invalidMetadata(identifier: kind.identifier, key: "ngramSize")
        }
        let minTermLength = try kind.requireInt("minTermLength")
        guard minTermLength > 0 else {
            throw .invalidMetadata(identifier: kind.identifier, key: "minTermLength")
        }

        self.init(
            fieldNames: kind.fieldNames,
            tokenizer: tokenizer,
            storePositions: try kind.requireBool("storePositions"),
            ngramSize: ngramSize,
            minTermLength: minTermLength
        )
    }
}
