/// A measured canonical RDF encoding that can initialize final storage directly.
///
/// The plan keeps the validated semantic value and exact byte count together so
/// callers do not need to allocate an intermediate payload before writing into
/// an enclosing database or wire frame.
public struct DatabaseRDFTermEncodingPlan: Sendable {
    package let term: DatabaseRDFTerm
    package let limits: DatabaseRDFTermCodecLimits
    public let byteCount: Int
    public let objectCount: Int
    public let maximumDepth: Int

    package init(
        term: DatabaseRDFTerm,
        limits: DatabaseRDFTermCodecLimits,
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
