
extension SpatialIndexKind {
    public init(
        canonical kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        try kind.validateIdentity(
            identifier: Self.identifier,
            subspaceStructure: Self.subspaceStructure
        )
        try kind.validateMetadataKeys(required: ["encoding", "level"])
        try kind.validateFieldCount(1)

        let rawEncoding = try kind.requireString("encoding")
        guard let encoding = SpatialEncoding(rawValue: rawEncoding) else {
            throw .invalidMetadata(identifier: kind.identifier, key: "encoding")
        }
        let level = try kind.requireInt("level")
        let maximumLevel = encoding == .morton ? 20 : 30
        guard (0...maximumLevel).contains(level) else {
            throw .invalidMetadata(identifier: kind.identifier, key: "level")
        }
        self.init(
            canonicalFields: kind.fields,
            encoding: encoding,
            level: level
        )
    }
}
