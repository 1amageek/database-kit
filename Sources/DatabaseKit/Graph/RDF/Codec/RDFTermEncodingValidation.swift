import DatabaseTypes

/// Proof produced by bounded validation of borrowed canonical RDF bytes.
public struct RDFTermEncodingValidation: Sendable, Equatable {
    public let kind: RDFTermKind
    public let fingerprint: RDFTermEncodingFingerprint
    public let objectCount: Int
    public let maximumDepth: Int

    package init(
        kind: RDFTermKind,
        fingerprint: RDFTermEncodingFingerprint,
        objectCount: Int,
        maximumDepth: Int
    ) {
        self.kind = kind
        self.fingerprint = fingerprint
        self.objectCount = objectCount
        self.maximumDepth = maximumDepth
    }
}
