import DatabaseKit
import DatabaseTypes

/// Proof produced by bounded validation of borrowed canonical RDF bytes.
struct RDFTermWireValidation: Sendable, Equatable {
    let kind: RDFTermKind
    let fingerprint: RDFTermWireFingerprint
    let objectCount: Int
    let maximumDepth: Int

    init(
        kind: RDFTermKind,
        fingerprint: RDFTermWireFingerprint,
        objectCount: Int,
        maximumDepth: Int
    ) {
        self.kind = kind
        self.fingerprint = fingerprint
        self.objectCount = objectCount
        self.maximumDepth = maximumDepth
    }
}
