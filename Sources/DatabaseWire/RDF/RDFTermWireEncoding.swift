import DatabaseTypes

/// A measured RDF wire representation that initializes a final frame directly.
///
/// The plan keeps the validated semantic value and exact byte count together so
/// callers do not need to allocate an intermediate payload before writing into
/// an enclosing DatabaseWire frame.
struct RDFTermWireEncoding: Sendable {
    let term: RDFTerm
    let limits: RDFTermWireLimits
    let byteCount: Int
    let objectCount: Int
    let maximumDepth: Int

    init(
        term: RDFTerm,
        limits: RDFTermWireLimits,
        byteCount: Int,
        objectCount: Int,
        maximumDepth: Int
    ) {
        self.term = term
        self.limits = limits
        self.byteCount = byteCount
        self.objectCount = objectCount
        self.maximumDepth = maximumDepth
    }
}
