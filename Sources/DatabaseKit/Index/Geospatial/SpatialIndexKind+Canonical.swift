
extension SpatialIndexKind {
    public init(
        canonical kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        try kind.validateIdentity(
            identifier: Self.identifier,
            subspaceStructure: Self.subspaceStructure
        )
        try kind.validateMetadataKeys(required: ["encoding", "level"])
        try kind.validateFieldCount(minimum: 2, maximum: 3)

        let rawEncoding = try kind.requireString("encoding")
        guard let encoding = SpatialEncoding(rawValue: rawEncoding) else {
            throw .invalidMetadata(identifier: kind.identifier, key: "encoding")
        }
        let level = try kind.requireInt("level")
        let maximumLevel = encoding == .morton && kind.fieldNames.count == 3 ? 20 : 30
        guard (0...maximumLevel).contains(level) else {
            throw .invalidMetadata(identifier: kind.identifier, key: "level")
        }
        guard encoding != .s2 || kind.fieldNames.count == 2 else {
            throw .invalidMetadata(identifier: kind.identifier, key: "encoding")
        }

        self.init(fieldNames: kind.fieldNames, encoding: encoding, level: level)
    }
}
