/// Proof produced by bounded validation of borrowed canonical RDF bytes.
public struct DatabaseRDFTermEncodingValidation: Sendable, Equatable {
    public let kind: DatabaseRDFTermKind
    public let fingerprint: DatabaseRDFTermEncodingFingerprint
    public let objectCount: Int
    public let maximumDepth: Int

    package init(
        kind: DatabaseRDFTermKind,
        fingerprint: DatabaseRDFTermEncodingFingerprint,
        objectCount: Int,
        maximumDepth: Int
    ) {
        self.kind = kind
        self.fingerprint = fingerprint
        self.objectCount = objectCount
        self.maximumDepth = maximumDepth
    }
}
